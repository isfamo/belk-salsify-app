# Read in file from tmp that has all Color Masters and their parents and all properties.
# For each child, get the Scene7 URL images, build out what their link text would be.
# Then map into the parent - at the child level map the same attribute to an empty string.

PER_ROW_LIMIT = 3
IMG_HEIGHT = 200 # in pixels
FILENAME = 'belk_export.csv'.freeze

task :build_html_attr_import do
    include Muffin::SalsifyClient

    #avoid_base_products = %w(1803510TD178052 3201602710591097011)
    avoid_base_products = []

    client ||= salsify_client(org_id: ENV.fetch('CARS_ORG_ID').to_i)
    base_products = {} # base_product_id => { link_text => url, link_text => url}
    child_products = []
    # I think we actually don't care about the parent knowing the children, we only care about knowing one's own parent
    #   leaving this here in case we want it
    track_children = {} # base_product_id => [child_id, child_id, child_id]
    track_dad = {} # child_id => parent_id

    # returns array where 0 is Shot and 1 is nrfColorCode
    def color_details_from_url(url)
        # e.g. http://s7d4.scene7.com/is/image/Belk?layer=0&src=5900090_S293_A_800_T10L00&layer=comp&
        search_string = '&src='
        return nil unless url.index(search_string)
        start_pos = url.index(search_string) + search_string.length
        end_pos = url.index('&', start_pos)
        color_details = url[start_pos, end_pos - start_pos].split('_')
        [color_details[2], color_details[3]]
    end

    # I think we can break up the URL to get the nrfColorCode and the Shot Type, but
    #   if that changes with the color key over thing, then not sure that will still work.
    # But looking in QA, it looks like these details do not all exist either - so not sure how best
    #   to populate. May need to get in there and then find out.
    puts "Reading CSV"
    t1 = Time.now
    #CSV.foreach("./tmp/belk_color_master_export.csv", {:col_sep => ",", :row_sep => "\n", :quote_char => '"', :encoding => 'utf-8', headers: true }) do |row|
    CSV.foreach("./tmp/#{FILENAME}", { :encoding => 'bom|utf-8', headers: true }) do |row|
        # need to get each url and build out what its link would be, then order that link and url by the ascending alphabetical sort of that link text
        # e.g. link text nrfColorCode_Shot_ColorText e.g. 330_A_blue or 441_B_light_gray
        # product_id = row['product_id'] <-- not using this
        is_grouping = false
        if row['salsify:parent_id'] && !avoid_base_products.include?(row['salsify:parent_id'])
            # this is a child
            track_children[row['salsify:parent_id']] = [] unless track_children[row['salsify:parent_id']]
            track_children[row['salsify:parent_id']] << row['product_id']
            track_dad[row['product_id']] = row['salsify:parent_id']
        elsif row['salsify:parent_id'].nil? && row['groupingType']
          # this is a grouping, use self as parent
          track_children[row['product_id']] = [] unless track_children[row['product_id']]
          track_children[row['product_id']] << row['product_id']
          track_dad[row['product_id']] = row['product_id']
          is_grouping = true
        else
          next
        end
        parent_id = is_grouping ? row['product_id'] : row['salsify:parent_id']
        child_products << row['product_id'] unless is_grouping

        row.each do |header_name, cell_value|
            next unless row['Color Master?']

            image_type = nil
            if header_name.downcase.include?('mainimage url')
              image_type = 'main'
            elsif header_name.downcase.include?('swatchimage url')
              image_type = 'swatch'
            else
              next
            end
            sku_id = row['product_id']

            if cell_value && cell_value.length > 45
                color_details = color_details_from_url(cell_value) # 0 is Shot, 1 is nrf color code
                next unless color_details

                nrf_color_code = row['nrfColorCode'] ? row['nrfColorCode'] : color_details[1]
                shot_type_match = header_name.match(/^.+-\ (.+)\ -.+$/)
                next unless shot_type_match
                shot_type = shot_type_match[1]
                color_text = row['omniChannelColorDescription'] ? row['omniChannelColorDescription'] : row['vendorColorDescription']

                link_text = "#{nrf_color_code}_#{shot_type}"
                link_text += "_#{color_text}" if color_text

                base_products[parent_id] = {} unless base_products[parent_id]
                base_products[parent_id][sku_id] = {} unless base_products[parent_id][sku_id]
                base_products[parent_id][sku_id][shot_type] = {} unless base_products[parent_id][sku_id][shot_type]
                base_products[parent_id][sku_id][shot_type][image_type] = { link_text => cell_value }
            end
        end
    end
    products = []
    # Iterate the base products and then build out their HTML
    puts "Building HTML for base products"
    base_products.each do |product_id, url_by_link_by_shot_by_img_type_by_sku_id|
        next if avoid_base_products.include?(product_id)
        row_count = 0

        # Make a row for each child SKU, ordering images main then swatch
        all_images_html = ' <div id="wrapper" style="text-align: center;"> '
        url_by_link_by_shot_by_img_type_by_sku_id.each do |sku_id, url_by_link_by_img_type_by_shot|
          url_by_link_by_img_type_by_shot.each do |shot_type, url_by_link_by_img_type|
            next if url_by_link_by_img_type['main'].nil? &&
              url_by_link_by_img_type['swatch'].nil?

            all_images_html += ' <div class="row"> '
            if url_by_link_by_img_type['main']
              link_text = url_by_link_by_img_type['main'].keys.first
              img_url = url_by_link_by_img_type['main'][link_text]
              all_images_html += " <div class=\"column\" style=\"display:inline-block;\"> <div class=\"container\"> <img src=\"#{img_url}\" height=\"#{IMG_HEIGHT}px\"> <p><a href=\"#{img_url}\">#{link_text}</a></p> </div> </div>"
            end
            if url_by_link_by_img_type['swatch']
              link_text = url_by_link_by_img_type['swatch'].keys.first
              img_url = url_by_link_by_img_type['swatch'][link_text]
              all_images_html += " <div class=\"column\" style=\"display:inline-block;\"> <div class=\"container\"> <img src=\"#{img_url}\" height=\"#{IMG_HEIGHT}px\"> <p><a href=\"#{img_url}\">#{link_text}</a></p> </div> </div>"
            end
            all_images_html += ' </div> '
            row_count += 1

          end
        end
        all_images_html += ' </div> '

        next if row_count == 0
        products << { 'product_id' => product_id, 'All Images' =>  all_images_html.gsub('\\','') }
    end
    # iterate the children and put in a blank value so that they don't inherit from the parent in the UI
    puts "Writing out empty children"
    child_products.each do |product_id|
        products << { 'product_id' => product_id, 'All Images' => ' ', 'salsify:parent_id' => track_dad[product_id] }
    end
puts "Took #{Time.now - t1} seconds"

# Build an import file
headers = {
        'header': {
          'mode': 'upsert',
          'scope': ['attributes',
                    { 'products': 'dynamic' }
                  ],
          'version': '2'
        }
      }
import_data = Array.new
import_data << headers
import_data << { 'attributes': [ { 'salsify:id' => 'product_id', 'salsify:role' => 'product_id' } , { 'salsify:id' => 'All Images', 'salsify:data_type' => 'html' } ] }
import_data << { 'products': products.uniq } # <-- looks like there is a scenario where these can be duped (or more accurately, the product ID is in there twice, but it must have diff data)

puts "Trying to import to 184832 in org 5041"
#puts import_data.to_json
File.write('belk_import.json', import_data.to_json)
import_run = Salsify::Utils::Import.start_import_with_new_file(client, 184832, StringIO.new(import_data.to_json), wait_until_complete: false)

end

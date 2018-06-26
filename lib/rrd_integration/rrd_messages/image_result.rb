module RRDonnelley
  class ImageResult

    attr_reader :image_id, :check, :reasons, :review_comments

    def initialize(image_id, check, reasons, review_comments)
      @image_id = image_id
      @check = check
      @reasons = reasons
      @review_comments = review_comments
    end

    def self.from_xml(child)
      image_id = child.attributes['image_id'].value
      check_tag = child.children.find { |item| item.name.downcase == 'check' }
      check = {
        'type' => check_tag.attributes['type'].value,
        'result' => check_tag.children.first.text
      }
      reasons_tag = child.children.find { |item| item.name.downcase == 'reasons' }
      if reasons_tag
        reasons = reasons_tag.children.reject do |child|
          child.is_a?(Nokogiri::XML::Text) && child.text.strip.empty?
        end.select do |child|
          child.name.downcase == 'reason'
        end.map do |reason|
          reason.text
        end
      end
      review_comments_tag = child.children.find { |item| item.name.downcase == 'reviewcomments' }
      if review_comments_tag
        review_comments = review_comments_tag.children.reject do |child|
          child.is_a?(Nokogiri::XML::Text) && child.text.strip.empty?
        end.select do |child|
          child.name.downcase == 'comment'
        end.map do |comment|
          comment.text
        end
      end
      new(image_id, check, reasons, review_comments)
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag!('image', 'image_id' => image_id) do |image|
        image.tag!('check', 'type' => check['type']) do |check_tag|
          check_tag << check['result']
        end
        if reasons
          image.tag!('reasons') do |reasons_tag|
            reasons.each do |reason|
              reasons_tag.tag!('reason', reason)
            end
          end
        end
        if review_comments
          image.tag!('reviewComments') do |review_comments_tag|
            review_comments.each do |comment|
              review_comments_tag.tag!('comment', comment)
            end
          end
        end
      end
      xml.target!
    end
  end
end

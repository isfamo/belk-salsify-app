namespace :iph do
  require_rel '../iph_mapping/**/*.rb'
  require_rel '../enrichment_integration/**/*.rb'

  task test: :environment do
    IphMapping::IphChange.process(
      5041,
      'testing',
      [
        {
          "salsify:id" => "1803388SKCA134195",
          "salsify:created_at" => "2017-11-30T22:38:30.425Z",
          "salsify:updated_at" => "2017-12-15T15:14:52.189Z",
          "salsify:version" => 81,
          "salsify:system_id" => "s-fe7374e5-c21b-4b75-8359-a021c0d112ee",
          "product_id" => "1803388SKCA134195",
          "demandCtr" => "32",
          "fobNumber" => "14",
          "demandCtrName" => "ACTIVEWEAR",
          "fobName" => "WOMENS",
          "iphCategory" => "Women > Pants_and_Leggings > Leggings",
          "isMaster" => "true",
          "vendorNumber" => "1803388",
          "Orin/Grouping #" => "300432411",
          "Dept#" => "723",
          "Dept Description" => "BE INSPIRED ACTIVEWR",
          "Class#" => "7162",
          "Class Description" => "LEGGINGS",
          "Style#" => "SKCA134195",
          "Vendor#" => "1803388",
          "Long Description" => "FLORAL CAMISOLE",
          "Item Status" => "Initialized",
          "edivenid" => "125103335555",
          "digital_content_required" => "Y",
          "isReadyForWeb" => true,
          "GXS Data Retrieved" => true,
          "gxs_closures" => "GM03CLOSHL",
          "gxs_fabric_description" => "100% Cotton",
          "gxs_feature_benefits" => [
            "High quality all weather fabric",
            "Anti-fading"
          ],
          "gxs_advertised_origin" => "GM03ADVOIM",
          "Last IPH GXS Mapping" => "Women > Pants_and_Leggings > Leggings",
          "Last GXS Pull Date" => "2017-12-14",
          "Last IPH GXS Mapping Date" => "2017-12-13",
          "Needs IPH Mapping" => false,
          "Is 2 Weeks past Turn-In?" => false,
          "Has Multiple Default SKU Codes" => false,
          "Link to Color Masters" => "https://app.salsify.com/app/orgs/s-32763a66-fe5c-4731-ab82-4ee816668005/products?filter=%3D%27Parent%20Product%27%3A%271803388SKCA134195%27%2C%27Color%20Master%3F%27%3A%27true%27%3Aproduct_type%3Aleaf"
        }
      ].to_json
    )
  end
end

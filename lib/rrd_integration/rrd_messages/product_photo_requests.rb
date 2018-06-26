module RRDonnelley
  class ProductPhotoRequests

    attr_reader :product_photo_requests

    def initialize(product_photo_requests)
      @product_photo_requests = product_photo_requests
    end

    def self.from_xml(child)
      new(child.children.select do |child|
        child.name.downcase == 'productphotorequest'
      end.map do |product_photo_request|
        ProductPhotoRequest.from_xml(product_photo_request)
      end)
    end

    def to_xml
      xml = Builder::XmlMarkup.new
      xml.tag!('productPhotoRequests') do |product_photo_requests_tag|
        product_photo_requests.each do |product_photo_request|
          product_photo_requests_tag << product_photo_request.to_xml
        end
      end
      xml.target!
    end

  end
end

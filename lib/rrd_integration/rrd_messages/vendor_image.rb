module RRDonnelley
  class VendorImage

    attr_reader :image_id, :name, :uploaded_by_user, :status

    def initialize(image_id, name, uploaded_by_user, status)
      @image_id = image_id
      @name = name
      @uploaded_by_user = uploaded_by_user
      @status = status
    end

    def self.from_xml(child)
      image_id = child.attributes['image_id'] ? child.attributes['image_id'].value : child.attributes['id'].value
      items = child.children.map { |item| [item.name.downcase, item.text] }.to_h
      new(image_id, items['name'], items['uploadedbyuser'], items['status'])
    end

    def to_xml(image_id_attribute: 'image_id')
      xml = Builder::XmlMarkup.new
      xml.tag!('vendorImage', image_id_attribute => image_id) do |vendorImage|
        vendorImage.tag!('name', name)
        vendorImage.tag!('uploadedByUser', uploaded_by_user)
        vendorImage.tag!('status', status)
      end
      xml.target!
    end

  end
end

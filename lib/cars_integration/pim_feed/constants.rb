module PIMFeed
  module Constants

    PARENT_ID = 'salsify:parent_id'.freeze
    PRODUCT_ID = 'product_id'.freeze
    ALL_IMAGES = 'All Images'.freeze

    COLOR_MASTER = 'Color Master?'.freeze
    COLOR_MASTER_SKU = 'Color Master SKU'.freeze
    COLOR_CODE_CLONE = 'nrfColorCodeClone'.freeze
    COLOR_CODE = 'nrfColorCode'.freeze
    REFINEMENT_COLOR = 'refinementColor'.freeze
    OMNI_COLOR = 'omniChannelColorDescription'.freeze
    VENDOR_COLOR = 'vendorColorDescription'.freeze
    EXISTING_PRODUCT = 'existing_product'.freeze
    GROUPING_TYPE = 'groupingType'.freeze
    HEX_COLOR = 'Hex_Color'.freeze
    IMG_HEIGHT = 200
    SIZE_CODE = 'nrfSizeCode'.freeze
    DEPT = 'Dept#'.freeze
    CLASS = 'Class#'.freeze
    SUPPLIER_SITE = 'Supplier Site'.freeze
    VENDOR_NUMBER = 'vendorNumber'.freeze

    # enrichment attributes
    OMNI_CHANNEL_COLOR = 'omniChannelColorDescription'.freeze
    REFINEMENT_COLOR = 'refinementColor'.freeze
    OMNI_SIZE = 'omniSizeDesc'.freeze
    REFINEMENT_SIZE = 'refinementSize'.freeze
    REFINEMENT_SUB_SIZE = 'Refinement SubSize'.freeze
    IPH_CATEGORY = 'iphCategory'.freeze
    OMNI_CHANNEL_BRAND = 'OmniChannel Brand'.freeze
    ENRICHMENT_STATUS = 'Product Enrichment Status'.freeze

    GXS_DATA_RETRIEVED = 'GXS Data Retrieved'.freeze

    ATTRIBUTES_TO_IGNORE = [
      'Material',
      'Care',
      'Copy Approval State',
      'CAProp65_Compliant',
      'Copy Care',
      'Exclusive',
      'Copy_Line_1',
      'Copy_Line_2',
      'Copy_Line_3',
      'Copy_Line_4',
      'Copy_Line_5',
      'Copy Material',
      'Default_SKU_Code',
      'Limited Edition',
      'Product Copy Text',
      REFINEMENT_COLOR,
      COLOR_CODE,
      COLOR_MASTER
    ].freeze

  end
end

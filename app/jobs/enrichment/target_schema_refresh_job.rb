module Enrichment
  class TargetSchemaRefreshJob < Struct.new(:user_email)

    def perform
      Enrichment::TargetSchema.generate_and_import(user_email)
    end

  end
end

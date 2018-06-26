module ImportIdHandler
  extend self

  COMPLETED = 'completed'.freeze

  def calculate_import_id(client, filename, import_id)
    import = client.import(import_id)
    return import_id if import.last_import_run.status == COMPLETED
    salsify_client.create_import(create_json_import_request_body(filename)).id
  end

  def create_json_import_request_body(filename)
    {
      import_format: { type: 'json_import_format' },
      import_source: {
        file: filename,
        type: 'upload_import_source',
        upload_path: filename
      }
    }
  end

end

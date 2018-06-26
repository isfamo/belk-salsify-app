module Demandware

  class S3Helper

    def initialize
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(
        region: ENV.fetch('AWS_REGION'),
        access_key_id: ENV.fetch('AWS_ACCESS_KEY_ID'),
        secret_access_key: ENV.fetch('AWS_SECRET_ACCESS_KEY')
      )
    end

    def upload_to_s3(bucket, key, body)
      s3_client.put_object(
        bucket: bucket,
        key: key,
        body: body
      )
    end

    def pull_from_s3(bucket, key)
      s3_client.get_object(
        bucket: bucket,
        key: key
      )
    rescue Aws::S3::Errors::NoSuchKey => e
      nil
    end

    def list_files(bucket, prefix)
      s3_client.list_objects(
        bucket: bucket,
        prefix: prefix
      ).contents.select do |object|
        object.key.split('/')[0..-2] == prefix.split('/') && # don't include things in subfolders
        object.key[-1] != '/' # don't include folders
      end
    end

    def list_files_updated_since(bucket, prefix, datetime)
      list_files(bucket, prefix).select do |object|
        object.last_modified > datetime
      end
    end

    def list_files_updated_between(bucket:, prefix:, since:, to:)
      list_files(bucket, prefix).select do |object|
        object.last_modified >= since && object.last_modified <= to
      end
    end

    def s3_resource_client
      @s3_resource_client ||= Aws::S3::Resource.new(client: Aws::S3::Client.new(
        credentials: Aws::Credentials.new(ENV.fetch('AWS_ACCESS_KEY_ID'), ENV.fetch('AWS_SECRET_ACCESS_KEY')),
        region: ENV.fetch('AWS_REGION')
      ))
    end

    def upload_resource_to_s3(bucket, key, filepath, tries = 1)
      s3_resource_client.bucket(bucket).object(key).upload_file(filepath)
    rescue Exception => e
      if tries < 4
        sleep 2
        tries += 1
        retry
      else
        puts "$DW$ ERROR while uploading resource to S3: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    def move_object(src_bucket:, src_key:, target_path:)
      Aws::S3::Object.new(bucket_name: src_bucket, key: src_key).move_to(target_path)
    end

  end

end

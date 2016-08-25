module DiscourseBackupUploadsToS3
  class FileEncryptor
    TMP_FOLDER = Rails.root.join('tmp')

    def initialize(secret_key)
      @box = RbNaCl::SimpleBox.from_secret_key(Base64.decode64(secret_key))
    end

    def encrypt(source, destination: nil, compress: false)
      if !destination && block_given?
        begin
          tmp_path = TMP_FOLDER.join(File.basename(source))

          File.open(source, 'rb') do |file|
            File.open(tmp_path, 'wb') do |enc_file|
              content = file.read
              content = compress_content(content) if compress
              enc_file.write(box_encrypt(content))
            end
          end

          yield(tmp_path)
        ensure
          File.delete(tmp_path) if File.exists?(tmp_path)
        end
      else
        File.open(source, 'rb') do |file|
          File.open(destination, 'wb') do |enc_file|
            content = file.read
            content = compress_content(content) if compress
            enc_file.write(box_encrypt(content))
          end
        end
      end
    end

    def decrypt(source, destination)
      compressed = (source =~ /\.gz\.?/) ? true : false

      File.open(source, 'rb') do |enc_file|
        File.open(destination, 'wb') do |file|
          content = box_decrypt(enc_file.read)
          content = decompress_content(content) if compressed
          file.write(content)
        end
      end
    end

    private

    def compress_content(content)
      ActiveSupport::Gzip.compress(content)
    end

    def decompress_content(content)
      ActiveSupport::Gzip.decompress(content)
    end

    def box_encrypt(content)
      @box.encrypt(content)
    end

    def box_decrypt(content)
      @box.decrypt(content)
    end
  end
end

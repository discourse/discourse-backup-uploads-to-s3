module DiscourseBackupUploadsToS3
  class FileEncryptor
    TMP_FOLDER = Rails.root.join('tmp')
    BUFFER_SIZE = 4096

    # https://github.com/cryptosphere/rbnacl/blob/0ea0ee22668422ef600601c2dc3a19014c559e70/lib/rbnacl/simple_box.rb#L20-L22
    NONCE_SIZE = 24
    AUTHENTICATOR_SIZE = 16

    def initialize(secret_key)
      @box = RbNaCl::SimpleBox.from_secret_key(Base64.decode64(secret_key))
    end

    def encrypt(source, destination=nil)
      if !destination || block_given?
        begin
          tmp_path = TMP_FOLDER.join(File.basename(source))

          File.open(source, 'rb') do |file|
            File.open(tmp_path, 'w+b') do |enc_file|
              # while buffer = file.read(BUFFER_SIZE)
                enc_file.write(box_encrypt(file.read))
              # end

              enc_file.rewind
              yield(enc_file)
            end
          end
        ensure
          File.delete(tmp_path) if File.exists?(tmp_path)
        end
      else
        File.open(source, 'rb') do |file|
          File.open(destination, 'wb') do |enc_file|
            # while buffer = file.read(BUFFER_SIZE)
              enc_file.write(box_encrypt(file.read))
            # end
          end
        end
      end
    end

    def decrypt(source, destination)
      File.open(source, 'rb') do |enc_file|
        File.open(destination, 'wb') do |file|
          # while buffer = enc_file.read(BUFFER_SIZE + NONCE_SIZE + AUTHENTICATOR_SIZE)
            file.write(box_decrypt(enc_file.read))
          # end
        end
      end
    end

    private

    def box_encrypt(text)
      @box.encrypt(text)
    end

    def box_decrypt(text)
      @box.decrypt(text)
    end
  end
end

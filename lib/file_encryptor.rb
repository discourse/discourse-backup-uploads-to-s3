module DiscourseBackupUploadsToS3
  class FileEncryptor
    TMP_FOLDER = Rails.root.join('tmp')

    def initialize(secret_key)
      @box = RbNaCl::SimpleBox.from_secret_key(Base64.decode64(secret_key))
    end

    def encrypt(source, destination=nil)
      if !destination || block_given?
        begin
          tmp_path = TMP_FOLDER.join(File.basename(source))

          File.open(source, 'rb') do |file|
            File.open(tmp_path, 'w+b') do |enc_file|
              enc_file.write(box_encrypt(file.read))
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
            enc_file.write(box_encrypt(file.read))
          end
        end
      end
    end

    def decrypt(source, destination)
      File.open(source, 'rb') do |enc_file|
        File.open(destination, 'wb') do |file|
          file.write(box_decrypt(enc_file.read))
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

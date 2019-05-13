# frozen_string_literal: true

require 'rails_helper'

describe DiscourseBackupUploadsToS3::FileEncryptor do
  let(:secret_key) { 'U6ocWTLaXcvIvX5nSCYch5jV02Z+H9YQXaaIo8aNV/E=\n' }

  subject { described_class.new(secret_key) }

  def encrypt_and_decrypt_file(file, compress: false)
    begin
      source = file.path
      destination = "#{source}.enc"
      destination = "#{source}.gz" if compress

      subject.encrypt(source, destination: destination, compress: compress)

      decrypted_destination = "#{File.dirname(source)}/output"
      subject.decrypt(destination, decrypted_destination)

      expect(File.read(decrypted_destination)).to eq(file.read)
    ensure
      File.delete(decrypted_destination) if File.exists?(decrypted_destination)
    end
  end

  it "should be able to encrypt and decrypt images correctly" do
    encrypt_and_decrypt_file(file_from_fixtures("logo.png"))
    encrypt_and_decrypt_file(file_from_fixtures("large & unoptimized.png"))
  end

  it "should be able to encrypt and decrypt images correctly with compression enabled" do
    encrypt_and_decrypt_file(file_from_fixtures("logo.png"), compress: true)
    encrypt_and_decrypt_file(file_from_fixtures("large & unoptimized.png"), compress: true)
  end

  it "should be able to encrypt and decrypt a csv file correctly" do
    encrypt_and_decrypt_file(file_from_fixtures("discourse.csv", "csv"))
  end

  it "should be able to encrypt and decrypt a scss file correctly" do
    encrypt_and_decrypt_file(file_from_fixtures("my_plugin.scss", "scss"))
  end

  it "should be able to encrypt and decrypt a YAML file correctly" do
    encrypt_and_decrypt_file(file_from_fixtures("client.yml", "site_settings"))
  end

  describe "#encrypt" do
    it "yields a file that can be read" do
      image = file_from_fixtures("logo.png")
      subject.encrypt(image.path) { |enc_file| enc_file.read(1) }
    end

    it "yields a compressed file that can be read" do
      image = file_from_fixtures("logo.png")
      destination = "#{File.dirname(image.path)}/logo.png.gz.enc"

      subject.encrypt(image.path, compress: true) do |enc_file|
        File.open("#{File.dirname(image.path)}/logo.png.gz.enc", "wb") do |file|
          file.write(enc_file.read)
        end
      end

      output = "#{File.dirname(image.path)}/output.png"
      subject.decrypt(destination, output)
      expect(File.read(output)).to eq(image.read)
    end
  end
end

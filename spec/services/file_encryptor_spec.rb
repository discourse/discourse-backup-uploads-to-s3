require 'rails_helper'

describe DiscourseBackupUploadsToS3::FileEncryptor do
  let(:secret_key) { 'U6ocWTLaXcvIvX5nSCYch5jV02Z+H9YQXaaIo8aNV/E=\n' }

  subject { described_class.new(secret_key) }

  def encrypt_and_decrypt_file(file)
    source = file.path
    destination = "#{source}.enc"

    subject.encrypt(source, destination)

    decrypted_destination = "#{File.dirname(source)}/output"
    subject.decrypt(destination, decrypted_destination)

    expect(File.read(decrypted_destination)).to eq(file.read)
  end

  it "should be able to encrypt and decrypt an image file correctly" do
    encrypt_and_decrypt_file(file_from_fixtures("logo.png"))
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
  end
end

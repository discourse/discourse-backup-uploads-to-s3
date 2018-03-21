require 'rails_helper'
require 'sidekiq/testing'

describe Jobs::BackupUploadToS3 do
  let(:user) { Fabricate(:user) }
  let(:file) { file_from_fixtures("logo.png") }

  let(:upload) do
    UploadCreator.new(file, "logo.png").create_for(user.id)
  end

  let(:upload_path) { "original/1X/#{upload.sha1}.png" }
  let(:s3_object) { stub }
  let(:s3_bucket) { stub }

  subject { Jobs::BackupUploadToS3.new }

  before do
    GlobalSetting.stubs(:backup_uploads_to_s3_enabled).returns(true)
    GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket')
    GlobalSetting.stubs(:backup_uploads_to_s3_access_key_id).returns('some key')
    GlobalSetting.stubs(:backup_uploads_to_s3_secret_access_key).returns('some secret key')
    GlobalSetting.stubs(:backup_uploads_to_s3_region).returns('us-west-1')
    GlobalSetting.stubs(:backup_uploads_to_s3_encryption_key).returns('U6ocWTLaXcvIvX5nSCYch5jV02Z+H9YQXaaIo8aNV/E=\n')

    @original_site_setting = SiteSetting.queue_jobs
    SiteSetting.queue_jobs = true
  end

  after do
    SiteSetting.queue_jobs = @original_site_setting
  end

  it 'should not do anything if upload is not found' do
    subject.execute(upload_id: -1)

    expect(PluginStore.get(
      DiscourseBackupUploadsToS3::PLUGIN_NAME,
      DiscourseBackupUploadsToS3::Utils.plugin_store_key(-1)
    )).to eq(nil)
  end

  it 'should not do anything if file is not found' do
    upload = Fabricate(:upload)
    subject.execute(upload_id: upload.id)

    expect(PluginStore.get(
      DiscourseBackupUploadsToS3::PLUGIN_NAME,
      DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
    )).to eq(nil)
  end

  describe '#backup_upload' do
    it "should store the upload on to s3" do
      DiscourseBackupUploadsToS3::FileEncryptor.any_instance.stubs(:encrypt).yields(file_from_fixtures("logo.png"))
      S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
      s3_bucket.expects(:object).with("default/#{upload_path}.enc").returns(s3_object)
      s3_object.expects(:upload_file)

      subject.execute(upload_id: upload.id)

      expect(PluginStore.get(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
      )).to eq("some-bucket/default/#{upload_path}.enc")
    end

    context 'when upload is not an image' do
      let(:file) { File.new("#{Rails.root}/spec/fixtures/csv/discourse.csv") }

      let(:upload) do
        UploadCreator.new(file, "discourse.csv").create_for(user.id)
      end

      let(:upload_path) { "original/1X/#{upload.sha1}.csv" }

      it 'should compress and store the upload on to s3' do
        SiteSetting.authorized_extensions = 'csv'

        DiscourseBackupUploadsToS3::FileEncryptor
          .any_instance.stubs(:encrypt)
          .yields(file)

        S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
        s3_bucket.expects(:object).with("default/#{upload_path}.gz.enc").returns(s3_object)
        s3_object.expects(:upload_file)

        subject.execute(upload_id: upload.id)

        expect(PluginStore.get(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
        )).to eq("some-bucket/default/#{upload_path}.gz.enc")
      end
    end

    context "when bucket name contains folders path" do
      before do
        GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket/path')
      end

      it "should store the upload on to s3" do
        DiscourseBackupUploadsToS3::FileEncryptor.any_instance.stubs(:encrypt).yields(file_from_fixtures("logo.png"))
        S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
        s3_bucket.expects(:object).with("path/default/#{upload_path}.enc").returns(s3_object)
        s3_object.expects(:upload_file)

        subject.execute(upload_id: upload.id)

        expect(PluginStore.get(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
        )).to eq("some-bucket/path/default/#{upload_path}.enc")
      end
    end
  end
end

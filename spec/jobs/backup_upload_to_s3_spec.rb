require 'rails_helper'
require 'sidekiq/testing'

describe Jobs::BackupUploadToS3 do
  let(:upload) { Fabricate(:upload) }
  let(:upload_path) { "original/1X/#{upload.sha1}.png" }
  let(:s3_object) { stub }
  let(:s3_bucket) { stub }
  let(:fixture_file) { file_from_fixtures("logo.png") }

  subject { Jobs::BackupUploadToS3.new }

  before do
    GlobalSetting.stubs(:backup_uploads_to_s3_enabled).returns(true)
    GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket')
    GlobalSetting.stubs(:backup_uploads_to_s3_access_key_id).returns('some key')
    GlobalSetting.stubs(:backup_uploads_to_s3_secret_access_key).returns('some secret key')
    GlobalSetting.stubs(:backup_uploads_to_s3_region).returns('us-west-1')
    GlobalSetting.stubs(:backup_uploads_to_s3_gnupg_public_key).returns('some public key')

    SiteSetting.queue_jobs = true
  end

  it 'should raise an error if upload is not found' do
    expect { subject.execute(upload_id: -1) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  describe '#backup_upload' do
    it "should store the upload on to s3" do
      Sidekiq::Testing.fake! do
        S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
        s3_bucket.expects(:object).with("default/#{upload_path}").returns(s3_object)
        s3_object.expects(:upload_file)

        subject.backup_upload(fixture_file, upload_path, upload.id)

        expect(PluginStore.get(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
        )).to eq("//some-bucket.s3.amazonaws.com/default/#{upload_path}")
      end
    end

    context "when bucket name contains folders path" do
      before do
        GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket/path')
      end

      it "should store the upload on to s3" do
        Sidekiq::Testing.fake! do
          S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
          s3_bucket.expects(:object).with("path/default/#{upload_path}").returns(s3_object)
          s3_object.expects(:upload_file)

          subject.backup_upload(fixture_file, upload_path, upload.id)

          expect(PluginStore.get(
            DiscourseBackupUploadsToS3::PLUGIN_NAME,
            DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
          )).to eq("//some-bucket.s3.amazonaws.com/path/default/#{upload_path}")
        end
      end
    end
  end
end

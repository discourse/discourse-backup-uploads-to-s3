require 'rails_helper'
require 'file_store/s3_store'

describe Jobs::BackupUploadToS3 do
  let(:upload) { Fabricate(:upload) }
  let(:s3_bucket) { stub }
  let(:s3_helper) { DiscourseBackupUploadsToS3::Utils.s3_helper }
  let(:store) { FileStore::S3Store.new(s3_helper, 'some-bucket') }
  let(:fixture_file) { file_from_fixtures("logo.png") }

  before do
    GlobalSetting.stubs(:backup_uploads_to_s3_enabled).returns(true)
    GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket')
    GlobalSetting.stubs(:backup_uploads_to_s3_access_key_id).returns('some key')
    GlobalSetting.stubs(:backup_uploads_to_s3_secret_access_key).returns('some secret key')
    GlobalSetting.stubs(:backup_uploads_to_s3_region).returns('us-west-1')
  end

  it 'should raise an error if upload is not found' do
    expect { Jobs::BackupUploadToS3.new.execute(upload_id: -1) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  describe '#backup_upload' do
    it "should store the upload on to s3" do
      s3_helper.expects(:s3_bucket).returns(s3_bucket)
      s3_object = stub

      s3_bucket.expects(:object).with("default/original/1X/#{upload.sha1}.png").returns(s3_object)
      s3_object.expects(:upload_file)

      Jobs::BackupUploadToS3.new.backup_upload(store, fixture_file, upload)

      expect(PluginStore.get(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
      )).to eq("//some-bucket.s3.amazonaws.com/default/original/1X/#{upload.sha1}.png")
    end

    context "when bucket name contains folders path" do
      before do
        GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket/path')
      end

      it "should store the upload on to s3" do
        s3_helper.expects(:s3_bucket).returns(s3_bucket)
        s3_object = stub

        s3_bucket.expects(:object).with("path/default/original/1X/#{upload.sha1}.png").returns(s3_object)
        s3_object.expects(:upload_file)

        Jobs::BackupUploadToS3.new.backup_upload(store, fixture_file, upload)

        expect(PluginStore.get(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
        )).to eq("//some-bucket.s3.amazonaws.com/path/default/original/1X/#{upload.sha1}.png")
      end
    end
  end
end

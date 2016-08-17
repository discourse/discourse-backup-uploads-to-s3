require 'rails_helper'
require 'sidekiq/testing'
require 'file_store/s3_store'

describe Jobs::RemoveUploadFromS3 do
  let(:upload) { Fabricate(:upload) }
  let(:fixture_file) { file_from_fixtures("logo.png") }

  before do
    GlobalSetting.stubs(:backup_uploads_to_s3_enabled).returns(true)
    GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket')
    GlobalSetting.stubs(:backup_uploads_to_s3_access_key_id).returns('some key')
    GlobalSetting.stubs(:backup_uploads_to_s3_secret_access_key).returns('some secret key')
    GlobalSetting.stubs(:backup_uploads_to_s3_region).returns('us-west-1')

    @original_site_setting = SiteSetting.queue_jobs
    SiteSetting.queue_jobs = true
  end

  after do
    SiteSetting.queue_jobs = @original_site_setting
  end

  describe "when arguments is not valid" do
    it "should raise an error" do
      expect { Jobs::RemoveUploadFromS3.new.execute(path: 'some/path') }
        .to raise_error(Discourse::InvalidParameters)

      expect { Jobs::RemoveUploadFromS3.new.execute(upload_id: upload.id) }
        .to raise_error(Discourse::InvalidParameters)
    end
  end

  it "should remove upload from s3" do
    plugin_store_key = DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)

    PluginStore.set(
      DiscourseBackupUploadsToS3::PLUGIN_NAME, plugin_store_key, 'some/url'
    )

    s3_bucket = stub
    s3_object = stub

    S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
    s3_bucket.expects(:object).with("default/tombstone/original/1X/#{upload.sha1}.png").returns(s3_object)
    s3_object.expects(:copy_from).with(copy_source: "some-bucket/default/original/1X/#{upload.sha1}.png")
    s3_bucket.expects(:object).with("default/original/1X/#{upload.sha1}.png").returns(s3_object)
    s3_object.expects(:delete)

    Jobs::RemoveUploadFromS3.new.execute(
      path: "original/1X/#{upload.sha1}.png", upload_id: upload.id
    )

    expect(PluginStore.get(
      DiscourseBackupUploadsToS3::PLUGIN_NAME, plugin_store_key
    )).to eq(nil)
  end

  context "when bucket name contains folder path" do
    before do
      GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket/path')
    end

    it "should remove upload from s3" do
      plugin_store_key = DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)

      PluginStore.set(
        DiscourseBackupUploadsToS3::PLUGIN_NAME, plugin_store_key, 'some/url'
      )

      s3_bucket = stub
      s3_object = stub

      S3Helper.any_instance.expects(:s3_bucket).returns(s3_bucket)
      s3_bucket.expects(:object).with("path/default/tombstone/original/1X/#{upload.sha1}.png").returns(s3_object)
      s3_object.expects(:copy_from).with(copy_source: "some-bucket/path/default/original/1X/#{upload.sha1}.png")
      s3_bucket.expects(:object).with("path/default/original/1X/#{upload.sha1}.png").returns(s3_object)
      s3_object.expects(:delete)

      Jobs::RemoveUploadFromS3.new.execute(
        path: "original/1X/#{upload.sha1}.png", upload_id: upload.id
      )

      expect(PluginStore.get(
        DiscourseBackupUploadsToS3::PLUGIN_NAME, plugin_store_key
      )).to eq(nil)
    end
  end
end

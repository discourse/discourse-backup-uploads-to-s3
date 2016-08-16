require 'rails_helper'
require 'sidekiq/testing'

describe Upload do
  let(:upload) { Fabricate(:upload) }

  before do
    @original_site_setting = SiteSetting.queue_jobs
    SiteSetting.queue_jobs = true

    DiscourseBackupUploadsToS3::Utils.expects(:backup_uploads_to_s3?)
      .returns(true).at_least_once

    GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket')
    GlobalSetting.stubs(:backup_uploads_to_s3_access_key_id).returns('some key')
    GlobalSetting.stubs(:backup_uploads_to_s3_secret_access_key).returns('some secret key')
    GlobalSetting.stubs(:backup_uploads_to_s3_region).returns('us-west-1')
  end

  after do
    SiteSetting.queue_jobs = @original_site_setting
  end

  it "should enqueue a job to backup upload to S3" do
    Sidekiq::Testing.fake! do
      expect { upload }.to change { ::Jobs::BackupUploadToS3.jobs.size }.by(1)
    end
  end

  it "should enqueue a job to remove upload from s3 when upload is destroyed" do
    Sidekiq::Testing.fake! do
      expect { upload.destroy }.to change { ::Jobs::RemoveUploadFromS3.jobs.size }.by(1)
    end
  end
end

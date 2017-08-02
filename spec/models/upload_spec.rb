require 'rails_helper'
require 'sidekiq/testing'

describe Upload do
  let(:upload) { Fabricate(:upload) }

  context "scopes" do
    describe '#not_backuped' do
      let(:upload2) { Fabricate(:upload) }

      it 'should return the right records' do
        upload

        PluginStore.set(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload2.id),
          "some_path"
        )

        uploads = Upload.not_backuped.to_a

        expect(uploads).to_not include(upload2)
        expect(uploads).to include(upload)
      end
    end
  end

  context 'callbacks' do
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
      expect { upload }.to change { ::Jobs::BackupUploadToS3.jobs.size }.by(1)
    end

    it "should only enqueue a job to backup upload to s3 when sha1 has changed" do
      upload

      expect { upload.update!(original_filename: 'test.png') }
        .to_not change { ::Jobs::BackupUploadToS3.jobs.size }

      expect { upload.update!(sha1: 'asdlkjasd') }
        .to change { ::Jobs::BackupUploadToS3.jobs.size }.by(1)
    end

    it "should enqueue a job to remove upload from s3 when upload is destroyed" do
      expect { upload.destroy }.to change { ::Jobs::RemoveUploadFromS3.jobs.size }.by(1)
    end
  end
end

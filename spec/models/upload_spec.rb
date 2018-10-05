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
      SiteSetting.queue_jobs = true

      GlobalSetting.stubs(:backup_uploads_to_s3_enabled).returns(true)
      GlobalSetting.stubs(:backup_uploads_to_s3_bucket).returns('some-bucket')
      GlobalSetting.stubs(:backup_uploads_to_s3_access_key_id).returns('some key')

      GlobalSetting.stubs(:backup_uploads_to_s3_secret_access_key)
        .returns('some secret key')

      GlobalSetting.stubs(:backup_uploads_to_s3_region).returns('us-west-1')

      GlobalSetting.stubs(:backup_uploads_to_s3_encryption_key)
        .returns('some-encryption-key')
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

      args = Jobs::RemoveUploadFromS3.jobs.first["args"].first

      expect(args["upload_id"]).to eq(upload.id)

      expect(args["path"]).to eq(
        "#{DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(upload)}.enc"
      )
    end

    describe 'when s3 uploads is enabled' do
      before do
        SiteSetting.s3_access_key_id = 'some_key'
        SiteSetting.s3_secret_access_key = 'some_secret'
        SiteSetting.enable_s3_uploads = true
      end

      it 'should not do anything' do
        expect { upload }.to_not change { ::Jobs::BackupUploadToS3.jobs.size }
      end
    end
  end
end

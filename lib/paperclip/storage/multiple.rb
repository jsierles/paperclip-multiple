module Paperclip
  module Storage
    ##
    # This is a Paperclip storage to work simultaneously with a filesystem and another backend (S3, riak, etc.)
    #
    # It's optimized to migrate from filesystem to another storage, so it's required that assets
    # always have their filesystem version to begin with.
    module Multiple
      def self.extended attachment
        if attachment.options[:multiple_if].call(attachment.instance)
          attachment.instance_eval do
            @filesystem  = Attachment.new(attachment.name, attachment.instance, attachment.options.merge(storage: :filesystem))
            @alt_storage = Attachment.new(attachment.name, attachment.instance, attachment.options.merge(storage: attachment.options[:alternate_storage]))

            # `after_flush_writes` closes files and unlinks them, but we have to read them twice to save them
            # on both storages, so we blank this one, and let the other attachment close the files.
            def @alt_storage.after_flush_writes; end
          end
        else
          attachment.extend Filesystem
        end
      end

      def filesystem
        @filesystem
      end

      def alt_storage
        @alt_storage
      end

      def display_from_alternate?
        @options[:display_from_alternate].call(instance) && use_multiple?
      end

      ##
      # This defaults to the filesystem version, since it's likely faster than querying other stores
      def exists?(style_name = default_style)
        filesystem.exists?
      end

      ##
      # Delegates to both filesystem and alternate stores.
      def flush_writes
        sync(:@queued_for_write)

        @alt_storage.flush_writes
        @filesystem.flush_writes

        @queued_for_write = {}
      end

      def queue_all_for_delete
        if use_multiple? && file?
          @filesystem.send  :queue_some_for_delete, *all_styles
          @alt_storage.send :queue_some_for_delete, *all_styles
        end
        super
      end

      ##
      # Delegates to both filesystem and alternate stores.
      def flush_deletes
        @filesystem.flush_deletes
        begin
          @alt_storage.flush_deletes
        rescue Excon::Errors::Error => e
          log("There was an unexpected error while deleting file from alternate storage: #{e}")
        end
        @queued_for_delete = []
      end

      ##
      # This defaults to the filesystem version, since it's a lot faster than querying s3.
      def copy_to_local_file(style, local_dest_path)
        @filesystem.copy_to_local_file(style, local_dest_path)
      end

      def url(style_name = default_style, options = {})
        if display_from_alternate?
          @alt_storage.url(style_name, options)
        elsif use_multiple?
          @filesystem.url(style_name, options)
        else
          super
        end
      end

      def path(style_name = default_style)
        if display_from_alternate?
          @alt_storage.path(style_name)
        elsif use_multiple?
          @filesystem.path(style_name)
        else
          super
        end
      end

      ##
      # These two are needed for a fog workaround - won't work with other stores
      def public_url(style = default_style)
        @alt_storage.public_url(style)
      end

      def expiring_url(time = (Time.now + 3600), style = default_style)
        @alt_storage.expiring_url(time, style)
      end

      private

      def all_styles
        [:original, *styles.keys]
      end

      def sync(ivar)
        @alt_storage.instance_variable_set(ivar, instance_variable_get(ivar))
        @filesystem.instance_variable_set(ivar, instance_variable_get(ivar))
      end

      def use_multiple?
        @options[:multiple_if].call(instance)
      end
    end
  end
end

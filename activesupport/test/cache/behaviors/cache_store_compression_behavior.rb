# frozen_string_literal: true

require "active_support/core_ext/numeric/bytes"
require "active_support/core_ext/object/with"

module CacheStoreCompressionBehavior
  extend ActiveSupport::Concern

  included do
    test "compression works with cache format version 6.1 (using Marshal61WithFallback)" do
      @cache = with_format(6.1) { lookup_store(compress: true) }
      assert_compression true
    end

    test "compression works with cache format version 7.0 (using Marshal70WithFallback)" do
      @cache = with_format(7.0) { lookup_store(compress: true) }
      assert_compression true
    end

    test "compression works with cache format version 7.1 (using Marshal71WithFallback)" do
      @cache = with_format(7.1) { lookup_store(compress: true) }
      assert_compression true
    end

    test "compression is disabled with custom coder" do
      @cache = with_format(7.1) { lookup_store(coder: Marshal) }
      assert_compression false
    end

    test "compression by default" do
      @cache = lookup_store
      assert_compression !compression_always_disabled_by_default?
    end

    test "compression can be disabled" do
      @cache = lookup_store(compress: false)
      assert_compression false
    end

    test ":compress method option overrides initializer option" do
      @cache = lookup_store(compress: true)
      assert_compression false, with: { compress: false }

      @cache = lookup_store(compress: false)
      assert_compression true, with: { compress: true }
    end

    test "low :compress_threshold triggers compression" do
      @cache = lookup_store(compress: true, compress_threshold: 1)
      assert_compression :all
    end

    test "high :compress_threshold inhibits compression" do
      @cache = lookup_store(compress: true, compress_threshold: 1.megabyte)
      assert_compression false
    end

    test ":compress_threshold method option overrides initializer option" do
      @cache = lookup_store(compress: true, compress_threshold: 1)
      assert_compression false, with: { compress_threshold: 1.megabyte }

      @cache = lookup_store(compress: true, compress_threshold: 1.megabyte)
      assert_compression :all, with: { compress_threshold: 1 }
    end

    test "compression ignores nil" do
      assert_not_compress nil
      assert_not_compress nil, with: { compress: true, compress_threshold: 1 }
    end

    test "compression ignores incompressible data" do
      assert_not_compress "", with: { compress: true, compress_threshold: 1 }
      assert_not_compress [*0..127].pack("C*"), with: { compress: true, compress_threshold: 1 }
    end
  end

  private
    # Use strings that are guaranteed to compress well, so we can easily tell if
    # the compression kicked in or not.
    SMALL_STRING = "0" * 100
    LARGE_STRING = "0" * 2.kilobytes

    SMALL_OBJECT = { data: SMALL_STRING }
    LARGE_OBJECT = { data: LARGE_STRING }

    def with_format(format_version, &block)
      ActiveSupport.deprecator.silence do
        ActiveSupport::Cache.with(format_version: format_version, &block)
      end
    end

    def assert_compress(value, **options)
      assert_operator compute_entry_size_reduction(value, **options), :>, 0
    end

    def assert_not_compress(value, **options)
      assert_equal 0, compute_entry_size_reduction(value, **options)
    end

    def assert_compression(compress, **options)
      if compress == :all
        assert_compress SMALL_STRING, **options
        assert_compress SMALL_OBJECT, **options
      else
        assert_not_compress SMALL_STRING, **options
        assert_not_compress SMALL_OBJECT, **options
      end

      if compress
        assert_compress LARGE_STRING, **options
        assert_compress LARGE_OBJECT, **options
      else
        assert_not_compress LARGE_STRING, **options
        assert_not_compress LARGE_OBJECT, **options
      end
    end

    def compute_entry_size_reduction(value, with: {})
      entry = ActiveSupport::Cache::Entry.new(value)

      uncompressed = @cache.send(:serialize_entry, entry, **with, compress: false)
      actual = @cache.send(:serialize_entry, entry, **with)

      uncompressed.bytesize - actual.bytesize
    end

    def compression_always_disabled_by_default?
      false
    end
end

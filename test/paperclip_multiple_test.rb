require 'test_helper'
require "paperclip/multiple"

class PaperclipMultipleTest < ActiveSupport::TestCase
  setup do
    User.alt_storage_enabled      = false
    User.display_from_alternate = false
  end

  teardown do
    User.delete_all
    alt_storage_directory.files.each(&:destroy) if alt_storage_directory.files.size > 0
  end

  test "behaves as a normal filesystem attachment" do
    @user = build_user

    assert File.exists?(@user.avatar.path)
    assert File.exists?(@user.avatar.path(:thumbnail))

    assert_equal 0, alt_storage_directory.files.size
    assert_nil @user.avatar.filesystem
    assert_nil @user.avatar.alt_storage
  end

  test "stores a file both locally and remotely" do
    User.alt_storage_enabled = true
    @user = build_user

    assert File.exists?(@user.avatar.filesystem.path)
    assert File.exists?(@user.avatar.filesystem.path(:thumbnail))

    assert_equal 2, alt_storage_directory.files.size
    assert alt_storage_directory.files.head(@user.avatar.alt_storage.path).present?
    assert alt_storage_directory.files.head(@user.avatar.alt_storage.path(:thumbnail)).present?
  end

  test "deleting deletes both" do
    User.alt_storage_enabled = true
    @user = build_user

    local_paths = [
      @user.avatar.filesystem.path,
      @user.avatar.filesystem.path(:thumbnail)
    ]

    s3_paths = [
      @user.avatar.alt_storage.path,
      @user.avatar.alt_storage.path(:thumbnail)
    ]

    assert_difference "alt_storage_directory.files.all.size", -2 do
      @user.destroy
    end

    assert !File.exists?(local_paths.first)
    assert !File.exists?(local_paths.last)

    assert alt_storage_directory.files.head(s3_paths.first).blank?
    assert alt_storage_directory.files.head(s3_paths.last).blank?
  end

  test "returns a local url" do
    User.alt_storage_enabled = true
    @user = build_user

    assert_equal "/uploads/users/avatars/000/000/001/original/image.jpg",  @user.avatar.url
    assert_equal "/uploads/users/avatars/000/000/001/thumbnail/image.jpg", @user.avatar.url(:thumbnail)
  end

  test "returns an amazon url" do
    User.alt_storage_enabled = true
    User.display_from_alternate = true
    @user = build_user

    assert_equal "https://#{FOG_DIRECTORY}.s3.amazonaws.com/uploads/users/avatars/000/000/001/original/image.jpg",  @user.avatar.url
    assert_equal "https://#{FOG_DIRECTORY}.s3.amazonaws.com/uploads/users/avatars/000/000/001/thumbnail/image.jpg", @user.avatar.url(:thumbnail)
  end

  test "returns a local url if display enabled but storage disabled" do
    User.alt_storage_enabled = false
    User.display_from_alternate = true
    @user = build_user

    assert_equal "/uploads/users/avatars/000/000/001/original/image.jpg",  @user.avatar.url
    assert_equal "/uploads/users/avatars/000/000/001/thumbnail/image.jpg", @user.avatar.url(:thumbnail)
  end

  private

  def build_user
    User.create id: 1, avatar: File.open('test/image.jpg')
  end

  def alt_storage_directory
    @directory  ||= alt_storage_connection.directories.new(key: FOG_DIRECTORY)
  end

  def alt_storage_connection
    @connection ||= Fog::Storage.new FOG_CREDENTIALS
  end
end

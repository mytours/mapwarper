require 'test_helper'

class ImportsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests ImportsController

  setup do
    admin_sign_in
    @import = FactoryBot.create(:import, user: @admin_user)
    @import.save
  end

  test 'create import' do
    assert_difference('Import.count', 1) do
      import_one_file = fixture_file_upload('data/imports/import_one.csv', 'text/csv')
      post :create, params: { import: { name: 'new import', metadata: import_one_file } }
    end
    assert_redirected_to import_path(Import.last)
    import = Import.last
    assert_equal 'new import', import.name
    assert_equal 1, import.file_count
  end

  test 'udpate import' do
    patch :update, params: { id: @import.id, import: { name: 'changed name' } }

    assert_redirected_to @import
    assert_equal 'changed name', @import.reload.name
  end

  test 'show import' do
    get :show, params: { id: @import.id }
    assert_response :ok
    assert_select 'h2', 'Import: test import'
  end

  test 'index import' do
    get :index
    assert_response :ok

    assert_select 'tr', 2  # two tr the thead row and the import
    assert_select 'a[href=?]', import_path(@import), text: @import.name
  end

  test 'start import' do
    Import.any_instance.stubs(:import!).returns(true)
    patch :start, params: { id: @import.id }
    assert_response :ok
    assert_select 'h2', 'Importing...'
  end

  test 'delete import' do
    assert_difference('Import.count', -1) do
      delete :destroy, params: { id: @import.id }
    end
    assert_redirected_to imports_path
    assert_equal 'Import deleted!', flash[:notice]
  end

  test 'maps of import' do
    map = FactoryBot.create(:basic_map, import_id: @import.id)
    map2 = FactoryBot.create(:unstubbed_map, import_id: @import.id)
    get :maps, params: { id: @import.id }
    assert_response :ok

    assert_select 'tr', 3  # two tr the thead row and the import

    assert_select 'a[href=?]', map_path(map), text: map.title
  end
end

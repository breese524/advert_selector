require File.dirname(__FILE__) + '/../test_helper'
#require 'test/test_helper'

class BannerShowsTest < ActionDispatch::IntegrationTest
  fixtures :all

  setup do
    @coke.reload
    @coke.fast_mode = true
    @coke.save!
    assert @coke.show_now_basics?, "fixtures problem"
    @pepsi.reload
    @pepsi.update_attribute(:confirmed, false)
    assert !@pepsi.show_now_basics?, "fixtures prolbem 2"
    AdvertSelector.admin_access_class = AdvertSelector::AdminAccessClassAlwaysTrue
  end

  def response_includes_banner?(banner)
    @response.body.include?(banner.helper_items.where(:content_for => true).last.content)
  end
  def assert_response_includes_banner(banner)
    assert response_includes_banner?(banner), "should have default banner content in response"
  end

  test "normal request and banner loading" do
    AdvertSelector::Banner.expects(:find_current).twice.returns(AdvertSelector::Banner.find_future)

    get '/'
    assert_response :success

    assert_response_includes_banner(@coke)

    assert $advert_selector_banners_load_time > 1.minute.ago
    original_time = $advert_selector_banners_load_time

    #assert_equal $advert_selector_banners, AdvertSelector::Banner.find_current

    get '/'
    assert_response :success

    assert_equal $advert_selector_banners_load_time, original_time

    Timecop.travel( 15.minutes.from_now ) do
      get '/'
      assert $advert_selector_banners_load_time != original_time
      assert $advert_selector_banners_load_time > 1.minute.ago
    end
  end

  test "only_once_per_session banners" do
    placement = @coke.placement
    placement.only_once_per_session = true
    placement.save!

    get '/'
    assert_response :success
    assert_response_includes_banner(@coke)

    assert_equal ["Leaderboard"], session["advert_selector_session_shown"], "should have info in session"

    get '/'
    assert_response :success
    assert !response_includes_banner?(@coke), "should not include banner on second view"
  end

  test "banner_frequency, limit frequency within one week" do
    @coke.update_attribute(:frequency, 2)

    get '/'
    assert_response :success
    assert_response_includes_banner(@coke)

    cookie_expiration_date_org = cookies.send(:eval, '@cookies').first.send(:eval, '@options')["expires"].to_time
    assert 6.days.from_now < cookie_expiration_date_org
    assert 7.days.from_now > cookie_expiration_date_org

    Timecop.travel( 3.days.from_now )

    get '/'
    assert_response :success
    assert_response_includes_banner(@coke)

    cookie_expiration_date_new = cookies.send(:eval, '@cookies').first.send(:eval, '@options')["expires"].to_time
    assert_equal cookie_expiration_date_new, cookie_expiration_date_org

    get '/'
    assert_response :success
    assert !response_includes_banner?(@coke), "should not include banner after expiration date"

  end

  test "HelperItem runned" do
    get '/'
    assert_response :success
    assert_response_includes_banner(@coke)

    $advert_selector_banners_load_time = nil

    @coke.helper_items.create!(:position => 0, :name => 'always_false')
    get '/'
    assert_response :success
    assert !response_includes_banner?(@coke), "should not include banner if helper_item returned false"

  end

  test "HelperItem with raising error and common error displays" do

    @coke.helper_items.create!(:position => 0, :name => 'raise_error')
    get '/'
    assert_response :success
    assert !response_includes_banner?(@coke), "should not include banner if helper_item raised error"

    get '/advert_selector/placements'
    assert_response :success
    assert_select '.alert-error', :text => /Error with banner Coke in placement Leaderboard/

  end


  test "complex setup conflicting banners placements" do
    @parade_banner.update_attributes!(:confirmed => true, :frequency => 1)
    get '/'
    assert_response :success
    assert response_includes_banner?(@parade_banner)
    assert !response_includes_banner?(@coke)

    get '/'
    assert_response :success
    assert !response_includes_banner?(@parade_banner)
    assert response_includes_banner?(@coke)
  end

  test "complex setup multiple banners placements" do
    @parade_banner.update_attributes!(:confirmed => true, :frequency => 1)
    @parade_banner.placement.conflicting_placements_array = ""
    @parade_banner.placement.save!

    get '/'
    assert_response :success
    assert response_includes_banner?(@parade_banner)
    assert response_includes_banner?(@coke)
  end

  test "banner preview url forces banner and displays information" do
    get '/'
    assert !response_includes_banner?(@parade_banner)
    assert_select '#advert_selector_info', :count => 0

    get "/?advert_selector_force=#{@parade_banner.id}&advert_selector_force_stamp=#{@parade_banner.start_time.to_i}"
    assert_response :success
    assert response_includes_banner?(@parade_banner)

    assert_select '#advert_selector_info', :count => 1
  end

end


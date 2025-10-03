require 'test_helper'

class UserWarningTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user)
    @warning = FactoryBot.create(:warning, user: @user, category: 'foo', status: 'open',
                                            note: 'maps are nice')
  end

  test 'be valid' do
    assert @warning.valid?
  end

  test 'still there user when deleted' do
    warning_id = @warning.id
    @user.destroy!

    warning = UserWarning.find warning_id
    assert warning.valid?
    assert_equal warning.note, 'maps are nice'
    assert_not warning.user
  end

  test 'can have two different warnings' do
    another_warning = FactoryBot.create(:warning, user: @user, category: 'bar', note: 'maps are great')
    assert another_warning.valid?
  end

  test 'can have two similar warnings but different statuses' do
    another_warning = FactoryBot.create(:warning, user: @user, category: 'foo', status: 'closed',
                                                   note: 'maps are great')
    assert another_warning.valid?
  end

  test 'cannot have two open warnings with the same category, user' do
    another_warning = FactoryBot.build(:warning, user: @user, category: 'foo', status: 'open',
                                                  note: 'maps are great')
    assert_not another_warning.valid?

    assert_raise ActiveRecord::RecordInvalid do
      FactoryBot.create(:warning, user: @user, category: 'foo', status: 'open', note: 'maps are great')
    end
  end

  test 'can have two warnings with the same category and user but non open statuses' do
    another_warning = FactoryBot.build(:warning, user: @user, category: 'foo', status: 'close',
                                                  note: 'maps are great')
    assert another_warning.valid?

    assert_nothing_raised ActiveRecord::RecordInvalid do
      FactoryBot.create(:warning, user: @user, category: 'foo', status: 'close', note: 'maps are great')
    end
  end
end

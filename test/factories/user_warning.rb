# frozen_string_literal: true

FactoryBot.define do
  factory :warning, class: 'UserWarning' do
    category { 'prune' }
    note { 'foo bar' }
    association :user
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :user, class: 'User' do
    sequence(:login) { |n| "user#{n}" }
    sequence(:email) { |n| "test#{n}@example.com" }
    password { 'password' }
    password_confirmation { 'password' }
    confirmed_at { Date.today }
  end

  factory :admin, class: 'User' do
    sequence(:login) { |n| "admin#{n}" }
    sequence(:email) { |n| "admin#{n}@example.com" }
    password { 'password' }
    password_confirmation { 'password' }
    confirmed_at { Date.today }
    after(:create) do |u|
      admin_role = FactoryBot.create(:admin_role)
      u.roles << admin_role
    end
  end

  factory :editor, class: 'User' do
    sequence(:login) { |n| "editor#{n}" }
    sequence(:email) { |n| "editor#{n}@example.com" }
    password { 'password' }
    password_confirmation { 'password' }
    confirmed_at { Date.today }
    after(:create) do |u|
      admin_role = FactoryBot.create(:editor_role)
      u.roles << admin_role
    end
  end
end

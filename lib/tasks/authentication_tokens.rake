namespace :users do
  desc 'Backfill authentication tokens for users missing them'
  task backfill_tokens: :environment do
    regenerated = 0
    skipped = 0

    User.find_each do |user|
      if user.authentication_token.present?
        skipped += 1
        next
      end

      user.ensure_authentication_token!
      regenerated += 1
    rescue StandardError => e
      Rails.logger.error("Failed to ensure authentication token for User ##{user.id}: #{e.message}")
      puts "Failed to ensure authentication token for User ##{user.id}: #{e.message}"
    end

    puts "Authentication token backfill complete"
    puts "  regenerated: #{regenerated}"
    puts "  skipped (already present): #{skipped}"
  end
end

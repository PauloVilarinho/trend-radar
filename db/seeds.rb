# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

if Rails.env.development?
  User.where(email: "admin@example.com").destroy_all
  User.find_or_create_by!(email: "admin@admin.com") do |user|
    user.password = "password"
    user.password_confirmation = "password"
  end
  Rails.logger.info "Seeded dev user: admin@admin.com / password"
end

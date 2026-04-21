namespace :admin do
  desc "Promote a user to admin by email: bin/rails 'admin:promote[email@example.com]'"
  task :promote, [ :email ] => :environment do |_t, args|
    email = args[:email].to_s.strip
    if email.empty?
      puts "Usage: bin/rails 'admin:promote[email@example.com]'"
      next
    end

    user = User.find_by(email: email)
    if user.nil?
      puts "user not found: #{email}"
    else
      user.update!(admin: true)
      puts "promoted #{user.email} to admin"
    end
  end
end

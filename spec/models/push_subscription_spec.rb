require "rails_helper"

RSpec.describe PushSubscription, type: :model do
  let(:user) { create(:user) }

  it "is valid with all required fields" do
    expect(build(:push_subscription, user: user)).to be_valid
  end

  it "requires endpoint" do
    expect(build(:push_subscription, user: user, endpoint: nil)).not_to be_valid
  end

  it "requires p256dh_key" do
    expect(build(:push_subscription, user: user, p256dh_key: nil)).not_to be_valid
  end

  it "requires auth_key" do
    expect(build(:push_subscription, user: user, auth_key: nil)).not_to be_valid
  end

  it "rejects duplicate endpoints for same user" do
    create(:push_subscription, user: user, endpoint: "https://push.example/abc")
    dup = build(:push_subscription, user: user, endpoint: "https://push.example/abc")
    expect(dup).not_to be_valid
  end
end

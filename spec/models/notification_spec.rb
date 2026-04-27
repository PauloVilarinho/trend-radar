require "rails_helper"

RSpec.describe Notification, type: :model do
  it "is valid with the default factory (pending web_push to a PushSubscription)" do
    expect(build(:notification)).to be_valid
  end

  it "rejects unknown channels" do
    expect(build(:notification, channel: "telegram")).not_to be_valid
  end

  it "rejects unknown statuses" do
    expect(build(:notification, status: "queued")).not_to be_valid
  end

  it "rejects unknown target types" do
    n = build(:notification, target_type: "User", target_id: 1)
    n.valid?
    expect(n.errors[:target_type]).to be_present
  end

  it "enforces uniqueness on (match, channel, target)" do
    first = create(:notification)
    duplicate = build(:notification,
                      match: first.match,
                      channel: first.channel,
                      target: first.target)
    expect(duplicate).not_to be_valid
  end
end

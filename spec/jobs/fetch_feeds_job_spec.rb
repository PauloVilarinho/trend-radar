require "rails_helper"

RSpec.describe FetchFeedsJob, type: :job do
  before do
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json")
      .to_return(status: 200, body: "[100, 101, 102]",
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/newstories.json")
      .to_return(status: 200, body: "[102, 103]",
                 headers: { "Content-Type" => "application/json" })
  end

  it "enqueues FetchStoryJob for each unique id in top+new (frequent mode)" do
    expect {
      FetchFeedsJob.new.perform("frequent")
    }.to have_enqueued_job(FetchStoryJob).exactly(4).times
  end

  it "refreshes young active stories that haven't been polled recently" do
    create(:story, hn_id: 200, hn_created_at: 1.hour.ago,
                   last_polled_at: 20.minutes.ago, tracking_status: "active")
    # An older story polled within the default cadence should be skipped.
    create(:story, hn_id: 201, hn_created_at: 10.hours.ago,
                   last_polled_at: 5.minutes.ago, tracking_status: "active")

    FetchFeedsJob.new.perform("frequent")

    expect(FetchStoryJob).to have_been_enqueued.with(200)
    expect(FetchStoryJob).not_to have_been_enqueued.with(201)
  end

  it "skips archived stories on the re-poll scan" do
    create(:story, hn_id: 300, tracking_status: "archived",
                   hn_created_at: 1.hour.ago, last_polled_at: 1.hour.ago)
    FetchFeedsJob.new.perform("frequent")
    expect(FetchStoryJob).not_to have_been_enqueued.with(300)
  end

  it "hits beststories.json on full mode" do
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/beststories.json")
      .to_return(status: 200, body: "[400]",
                 headers: { "Content-Type" => "application/json" })

    FetchFeedsJob.new.perform("full")

    expect(FetchStoryJob).to have_been_enqueued.with(400)
  end

  it "re-polls older active stories on the default cadence" do
    create(:story, hn_id: 500, hn_created_at: 24.hours.ago,
                   last_polled_at: 45.minutes.ago, tracking_status: "active")
    FetchFeedsJob.new.perform("frequent")
    expect(FetchStoryJob).to have_been_enqueued.with(500)
  end
end

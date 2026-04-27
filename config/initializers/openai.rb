OpenAI.configure do |c|
  c.access_token = ENV.fetch("OPENAI_API_KEY") do
    Rails.application.credentials.dig(:openai, :api_key)
  end
  c.request_timeout = 30
end

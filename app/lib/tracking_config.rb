module TrackingConfig
  extend self

  def velocity_candidate_threshold
    data.fetch(:velocity_candidate_threshold)
  end

  def archive
    data.fetch(:archive)
  end

  def match
    data.fetch(:match)
  end

  def snapshot_retention_days
    data.fetch(:snapshot_retention_days)
  end

  private

  def data
    @data ||= YAML.load_file(Rails.root.join("config/tracking.yml")).deep_symbolize_keys
  end
end

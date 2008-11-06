class String
  def to_url
    self.
      sub(%r{^[^:]+://}, "").     # Removes protocol
      sub(%r{^www\.}, "").        # Removes www
      sub(%r{\?.*$}, "").         # Removes trailing parameters
      sub(%r{index\.html$}, "").  # Removes trailing index.html
      sub(%r{/$}, "")             # Removes trailing slash
  end

  def human_sortify
    self.
      gsub(/^The\s/i,'').
      gsub(/^An?\s/i,'').
      downcase
  end
end


SimpleCov.start do
  enable_coverage :branch

  # Exclude test files from coverage
  add_filter "/test/"
end

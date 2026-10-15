SimpleCov.configure do
  skip '/spec/'
  enable_coverage :branch
end

if defined?(SimpleCov)
  SimpleCov.minimum_coverage line: 90, branch: 78
end

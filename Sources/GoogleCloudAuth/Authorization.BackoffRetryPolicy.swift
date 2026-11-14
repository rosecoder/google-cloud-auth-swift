import RetryableTask

extension Authorization {

  /// Retries with an exponentially increasing, jittered delay, so brief outages of the token
  /// endpoint (such as the metadata server) are ridden out without retrying in lockstep.
  struct BackoffRetryPolicy: RetryPolicy {

    let initialDelay: Duration
    let maximumDelay: Duration
    let maxRetries: UInt

    private var retryCount: UInt = 0

    /// With the defaults, the total delay is at most 12.7 seconds over 8 retries.
    init(
      initialDelay: Duration = .milliseconds(100),
      maximumDelay: Duration = .milliseconds(3200),
      maxRetries: UInt = 8
    ) {
      self.initialDelay = initialDelay
      self.maximumDelay = maximumDelay
      self.maxRetries = maxRetries
    }

    var shouldRetry: Bool {
      retryCount < maxRetries
    }

    mutating func beforeRetry() async throws {
      let delay = delay(forRetry: retryCount)
      retryCount += 1
      try await Task.sleep(for: delay * Double.random(in: 0.5...1))
    }

    /// The delay before jitter is applied.
    func delay(forRetry retry: UInt) -> Duration {
      var delay = initialDelay
      for _ in 0..<retry {
        delay *= 2
        if delay >= maximumDelay {
          return maximumDelay
        }
      }
      return min(delay, maximumDelay)
    }
  }
}

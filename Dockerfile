FROM ruby:3.2

# Create app directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy the rest of the code
COPY . .

# Default command
CMD ["ruby", "script.rb"]

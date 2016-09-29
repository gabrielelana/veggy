use Mix.Config

# Disable logger when running tests
config :logger, :console,
  level: :warn,
  format: "$date $time [$level] $levelpad$message\n",
  colors: [info: :green]

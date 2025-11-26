class Musicapp < Formula
  desc "Self-hosted music library (Gin backend + Vue frontend)"
  homepage "https://github.com/Zimodrok/InformNetw-public"
  url "https://github.com/Zimodrok/InformNetw-public.git", tag: "v0.1.11", revision: "670bd179d240d171a8148d68772b87d88ec6e41d"
  head "https://github.com/Zimodrok/InformNetw-public.git", branch: "main"
  license "MIT"

  depends_on "go" => :build
  depends_on "node" => :build
  depends_on "taglib"
  depends_on "postgresql"
  depends_on "rclone"

  def install
    # Build frontend
    cd "vue" do
      system "npm", "install"
      system "npm", "run", "build"
      pkgshare.install "dist"
    end

    # Build backend
    cd "Gin" do
      system "go", "build", "-o", bin/"musicapp"
    end

    pkgshare.install "sql"
    pkgshare.install ".env.example"
  end

  def post_install
    require "securerandom"
    require "json"
    require "uri"

    config_path = Pathname.new(File.expand_path("~/.config/musicapp/ports.json"))
    config_path.dirname.mkpath

    defaults = {
      "api_port" => 8080,
      "frontend_port" => 4173,
      "sftp_port" => 9824,
      "db_url" => "postgres://musicapp:@localhost:5432/musicapp?sslmode=disable",
    }

    config = defaults.dup
    if config_path.exist?
      parsed = JSON.parse(config_path.read) rescue {}
      config.merge!(parsed)
    else
      config_path.write(JSON.pretty_generate(config))
    end

    key_file = etc/"musicapp.env"
    unless key_file.exist?
      key_file.write("SFTP_MASTER_KEY=#{SecureRandom.base64(32)}\n")
      key_file.chmod(0o600)
    end

    chmod 0o755, pkgshare/"sql/init_db.sh" if File.exist?(pkgshare/"sql/init_db.sh")

    pg_bin = Formula["postgresql@14"].opt_bin
    psql = pg_bin/"psql"
    createuser = pg_bin/"createuser"
    createdb = pg_bin/"createdb"

    db_url = ENV["DATABASE_URL"].to_s
    db_url = config["db_url"].to_s if db_url.empty?
    host = ENV["PGHOST"].to_s
    if host.empty?
      begin
        host = URI.parse(db_url).host || "localhost"
      rescue URI::InvalidURIError
        host = "localhost"
      end
    end

    env = {
      "PGHOST" => host,
      "PGUSER" => ENV.fetch("PGUSER", "postgres").to_s,
      "DATABASE_URL" => db_url,
    }

    unless system(env, psql.to_s, "-tAc", "SELECT 1")
      opoo "PostgreSQL is not running; skipping automatic DB setup"
      return
    end

    has_user = system(env, psql.to_s, "-tAc", "SELECT 1 FROM pg_roles WHERE rolname='musicapp'")
    system(env, createuser.to_s, "-s", "musicapp") unless has_user

    has_db = system(env, psql.to_s, "-tAc", "SELECT 1 FROM pg_database WHERE datname='musicapp'")
    system(env, createdb.to_s, "-O", "musicapp", "musicapp") unless has_db

    system(env, (pkgshare/"sql/init_db.sh").to_s)

  rescue StandardError => e
    opoo "Automatic database setup failed: #{e}"
  end

  service do
    require "securerandom"

    run [opt_bin/"musicapp"]
    key_file = etc/"musicapp.env"
    master_key = ENV["SFTP_MASTER_KEY"]
    if master_key.to_s.empty? && key_file.exist?
      master_key = key_file.read.to_s.strip.split("=", 2).last.to_s
    end
    master_key = SecureRandom.base64(32) if master_key.to_s.empty?

    config_path = Pathname.new(File.expand_path("~/.config/musicapp/ports.json"))
    db_url = ENV["DATABASE_URL"].to_s
    db_url = config_path.read[/\"db_url\"\s*:\s*\"([^\"]+)\"/, 1] if db_url.empty? && config_path.exist?

    brew_prefix = HOMEBREW_PREFIX
    environment_variables(
      DATABASE_URL: db_url.empty? ? "postgres://musicapp:@localhost:5432/musicapp?sslmode=disable" : db_url,
      DIST_DIR: "#{opt_pkgshare}/dist",
      MUSICAPP_CONFIG: config_path.to_s,
      SFTP_MASTER_KEY: master_key,
      PATH: "#{brew_prefix}/bin:#{brew_prefix}/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
    )
    keep_alive true
    log_path var/"log/musicapp.log"
    error_log_path var/"log/musicapp.log"
  end

  def caveats
    <<~EOS
      Set DATABASE_URL (and optionally DISCOGS_KEY/DISCOGS_SECRET) before running.
      Initialize the database with: #{pkgshare}/sql/init_db.sh
      Frontend assets installed to: #{pkgshare}/dist
    EOS
  end

  test do
    assert_predicate bin/"musicapp", :exist?
  end
end

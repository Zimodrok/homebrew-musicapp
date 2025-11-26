class Musicapp < Formula
  desc "Self-hosted music library (Gin backend + Vue frontend)"
  homepage "https://github.com/Zimodrok/InformNetw-public"
  url "https://github.com/Zimodrok/InformNetw-public.git", tag: "v0.1.6", revision: "c26a6f9bf456c481e44162611d398f8de3db33d0"
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

    env = {
      "PGHOST" => ENV.fetch("PGHOST", "localhost").to_s,
      "PGUSER" => ENV.fetch("PGUSER", "postgres").to_s,
    }

    unless system(env, psql.to_s, "-tAc", "SELECT 1")
      opoo "PostgreSQL is not running; skipping automatic DB setup"
      return
    end

    has_user = system(env, psql.to_s, "-tAc", "SELECT 1 FROM pg_roles WHERE rolname='musicapp'")
    system(env, createuser.to_s, "-s", "musicapp") unless has_user

    has_db = system(env, psql.to_s, "-tAc", "SELECT 1 FROM pg_database WHERE datname='musicapp'")
    system(env, createdb.to_s, "-O", "musicapp", "musicapp") unless has_db

    host = env["PGHOST"]
    db_url = "postgres://musicapp:@#{host}:5432/musicapp?sslmode=disable"
    system(env.merge("DATABASE_URL" => db_url), (pkgshare/"sql/init_db.sh").to_s)

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

    brew_prefix = HOMEBREW_PREFIX
    environment_variables(
      DATABASE_URL: "postgres://musicapp:@localhost:5432/musicapp?sslmode=disable",
      DIST_DIR: "#{opt_pkgshare}/dist",
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

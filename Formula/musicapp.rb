class Musicapp < Formula
  desc "Self-hosted music library (Gin backend + Vue frontend)"
  homepage "https://github.com/Zimodrok/InformNetw"
  url "https://github.com/Zimodrok/InformNetw.git", tag: "v0.1.0", revision: "2d1a4d2d62218708c78e31c24f95d9db9b1f8567"
  head "https://github.com/Zimodrok/InformNetw.git", branch: "main"
  license "MIT"

  depends_on "go" => :build
  depends_on "node" => :build
  depends_on "taglib"
  depends_on "postgresql"

  def install
    # Build frontend
    cd "vue" do
      system "npm", "install"
      system "npm", "run", "build"
      (pkgshare/"dist").install Dir["dist/**/*"]
    end

    # Build backend
    system "go", "build", "-o", bin/"musicapp", "./Gin"

    pkgshare.install "sql"
    pkgshare.install ".env.example"
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

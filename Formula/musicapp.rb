class Musicapp < Formula
  desc "Self-hosted music library (Gin backend + Vue frontend)"
  homepage "https://github.com/Zimodrok/InformNetw-public"
  url "https://github.com/Zimodrok/InformNetw-public.git", tag: "v0.1.0", revision: "76beac018e01fe18ed1fd80fda50f28355b887a6"
  head "https://github.com/Zimodrok/InformNetw-public.git", branch: "main"
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
      pkgshare.install "dist"
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

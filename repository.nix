{
  id = "metarepo";
  origin = "Metarepo";
  label = "Metarepo Linux packages";
  url = "https://alturalabscr.github.io/metarepo";
  channels = {
    jammy = { format = "apt"; releases = [ "ubuntu2204" ]; };
    noble = {
      format = "apt";
      releases = [ "ubuntu2404" "ubuntu2604" "debian13" "linuxmint7" ];
    };
    fedora = { format = "dnf"; releases = [ "fedora44" ]; };
    arch = { format = "pacman"; releases = [ "arch" ]; };
  };
}

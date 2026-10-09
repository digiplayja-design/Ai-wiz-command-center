// Font binaries are unmodified upstream releases. See assets/logo_fonts/sources.json.
class LogoFont {
  const LogoFont(
    this.name,
    this.category,
    this.slug, {
    this.weight = 400,
    this.variable = false,
  });
  final String name, category, slug;
  final int weight;
  final bool variable;
  String get family => 'Korlix_$slug';
  String get asset => 'assets/logo_fonts/$slug.ttf';
  String get license => 'assets/logo_fonts/$slug-OFL.txt';
}

const logoFontCategories = [
  'All fonts',
  'Sans',
  'Serif',
  'Display',
  'Script',
  'Mono',
  'Classic',
];
const logoFontCatalog = <LogoFont>[
  LogoFont('Poppins', 'Sans', 'poppins', weight: 600, variable: false),
  LogoFont('Montserrat', 'Sans', 'montserrat', weight: 400, variable: true),
  LogoFont('Manrope', 'Sans', 'manrope', weight: 400, variable: true),
  LogoFont(
    'Space Grotesk',
    'Sans',
    'spacegrotesk',
    weight: 400,
    variable: true,
  ),
  LogoFont('Outfit', 'Sans', 'outfit', weight: 400, variable: true),
  LogoFont('Quicksand', 'Sans', 'quicksand', weight: 400, variable: true),
  LogoFont('Josefin Sans', 'Sans', 'josefinsans', weight: 400, variable: true),
  LogoFont('Raleway', 'Sans', 'raleway', weight: 400, variable: true),
  LogoFont(
    'Playfair Display',
    'Serif',
    'playfairdisplay',
    weight: 400,
    variable: true,
  ),
  LogoFont(
    'Cormorant Garamond',
    'Serif',
    'cormorantgaramond',
    weight: 400,
    variable: true,
  ),
  LogoFont('Lora', 'Serif', 'lora', weight: 400, variable: true),
  LogoFont(
    'Libre Baskerville',
    'Serif',
    'librebaskerville',
    weight: 400,
    variable: true,
  ),
  LogoFont(
    'DM Serif Display',
    'Serif',
    'dmserifdisplay',
    weight: 400,
    variable: false,
  ),
  LogoFont('Bodoni Moda', 'Serif', 'bodonimoda', weight: 400, variable: true),
  LogoFont('Fraunces', 'Serif', 'fraunces', weight: 400, variable: true),
  LogoFont('Cinzel', 'Serif', 'cinzel', weight: 400, variable: true),
  LogoFont('Bebas Neue', 'Display', 'bebasneue', weight: 400, variable: false),
  LogoFont('Anton', 'Display', 'anton', weight: 400, variable: false),
  LogoFont(
    'Abril Fatface',
    'Display',
    'abrilfatface',
    weight: 400,
    variable: false,
  ),
  LogoFont(
    'Alfa Slab One',
    'Display',
    'alfaslabone',
    weight: 400,
    variable: false,
  ),
  LogoFont('Bungee', 'Display', 'bungee', weight: 400, variable: false),
  LogoFont('Righteous', 'Display', 'righteous', weight: 400, variable: false),
  LogoFont('Fredoka', 'Display', 'fredoka', weight: 400, variable: true),
  LogoFont('Orbitron', 'Display', 'orbitron', weight: 400, variable: true),
  LogoFont('Pacifico', 'Script', 'pacifico', weight: 400, variable: false),
  LogoFont('Lobster', 'Script', 'lobster', weight: 400, variable: false),
  LogoFont('Caveat', 'Script', 'caveat', weight: 400, variable: true),
  LogoFont(
    'Dancing Script',
    'Script',
    'dancingscript',
    weight: 400,
    variable: true,
  ),
  LogoFont('Allura', 'Script', 'allura', weight: 400, variable: false),
  LogoFont('Space Mono', 'Mono', 'spacemono', weight: 700, variable: false),
  LogoFont(
    'IBM Plex Mono',
    'Mono',
    'ibmplexmono',
    weight: 600,
    variable: false,
  ),
  LogoFont('Inconsolata', 'Mono', 'inconsolata', weight: 400, variable: true),
];
const logoTypefaces = [
  'Clean',
  'Strong',
  'Wide',
  'Slanted',
  'Poppins',
  'Montserrat',
  'Manrope',
  'Space Grotesk',
  'Outfit',
  'Quicksand',
  'Josefin Sans',
  'Raleway',
  'Playfair Display',
  'Cormorant Garamond',
  'Lora',
  'Libre Baskerville',
  'DM Serif Display',
  'Bodoni Moda',
  'Fraunces',
  'Cinzel',
  'Bebas Neue',
  'Anton',
  'Abril Fatface',
  'Alfa Slab One',
  'Bungee',
  'Righteous',
  'Fredoka',
  'Orbitron',
  'Pacifico',
  'Lobster',
  'Caveat',
  'Dancing Script',
  'Allura',
  'Space Mono',
  'IBM Plex Mono',
  'Inconsolata',
];
LogoFont logoFontFor(String face) => logoFontCatalog.firstWhere(
  (font) => font.name == face,
  orElse: () => const LogoFont('Roboto', 'Classic', 'roboto'),
);
bool isClassicLogoFont(String face) =>
    !logoFontCatalog.any((font) => font.name == face);
String logoFontFamily(String face) =>
    isClassicLogoFont(face) ? 'KorlixLogo' : logoFontFor(face).family;
int logoFontWeight(String face) =>
    face == 'Strong' ? 700 : logoFontFor(face).weight;

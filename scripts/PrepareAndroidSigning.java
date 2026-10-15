import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.Properties;

// Reuse the original Codespace's upload key without editing its files or
// printing passwords. Match android/app/build.gradle.kts property precedence.
class PrepareAndroidSigning {
    private static String setting(Properties properties, String name, String... envNames) {
        String value = properties.getProperty(name, "").trim();
        if (!value.isEmpty()) return value;
        for (String envName : envNames) {
            value = System.getenv(envName);
            if (value != null && !value.trim().isEmpty()) return value.trim();
        }
        return "";
    }

    private static void writePrivateProperties(Path target, Properties properties) throws Exception {
        Files.createFile(target, PosixFilePermissions.asFileAttribute(
            PosixFilePermissions.fromString("rw-------")));
        try (OutputStream output = Files.newOutputStream(target)) {
            properties.store(output, "Local Android build configuration; do not commit");
        }
    }

    public static void main(String[] args) {
        try {
            if (args.length != 2) throw new IllegalArgumentException();
            Path original = Path.of(args[0]).toRealPath().resolve("android");
            Path destination = Path.of(args[1]).toRealPath().resolve("android");
            if (original.equals(destination)) throw new IllegalArgumentException();
            Properties existing = new Properties();
            try (InputStream input = Files.newInputStream(original.resolve("key.properties"))) {
                existing.load(input);
            }
            String configured = setting(existing, "storeFile", "KORLIX_ANDROID_STORE_FILE",
                "ANDROID_KEYSTORE_PATH", "CM_KEYSTORE_PATH");
            Path keystore = null;
            for (String candidate : new String[] {configured, "app/korlix-release-key.jks", "korlix-release-key.jks"}) {
                if (!candidate.isBlank() && Files.isRegularFile(original.resolve(candidate))) {
                    keystore = original.resolve(candidate).toRealPath();
                    break;
                }
            }
            if (keystore == null) {
                System.err.println("The existing signing file was found, but its keystore is missing.");
                System.exit(1);
            }
            Properties signing = new Properties();
            signing.setProperty("storeFile", keystore.toString());
            signing.setProperty("storePassword", setting(existing, "storePassword",
                "KORLIX_ANDROID_STORE_PASSWORD", "ANDROID_KEYSTORE_PASSWORD", "CM_KEYSTORE_PASSWORD"));
            signing.setProperty("keyAlias", setting(existing, "keyAlias",
                "KORLIX_ANDROID_KEY_ALIAS", "ANDROID_KEY_ALIAS", "CM_KEY_ALIAS"));
            signing.setProperty("keyPassword", setting(existing, "keyPassword",
                "KORLIX_ANDROID_KEY_PASSWORD", "ANDROID_KEY_PASSWORD", "CM_KEY_PASSWORD"));
            for (String name : new String[] {"storePassword", "keyAlias", "keyPassword"}) {
                if (signing.getProperty(name).isEmpty()) {
                    System.err.println("The existing release signing configuration is incomplete: " + name);
                    System.exit(1);
                }
            }
            // Flutter regenerates its local settings. Preserve only an existing
            // Android SDK location if the Codespace relies on local.properties.
            Path originalLocal = original.resolve("local.properties");
            Properties local = new Properties();
            if (Files.isRegularFile(originalLocal)) {
                Properties allLocal = new Properties();
                try (InputStream input = Files.newInputStream(originalLocal)) {
                    allLocal.load(input);
                }
                String sdk = allLocal.getProperty("sdk.dir", "").trim();
                if (!sdk.isEmpty()) local.setProperty("sdk.dir", original.resolve(sdk).normalize().toString());
            }
            Path target = destination.resolve("key.properties");
            Path targetLocal = destination.resolve("local.properties");
            if (Files.exists(target) || (!local.isEmpty() && Files.exists(targetLocal))) {
                System.err.println("The build folder already contains local signing or SDK settings; nothing was overwritten.");
                System.exit(1);
            }
            writePrivateProperties(target, signing);
            if (!local.isEmpty()) writePrivateProperties(targetLocal, local);
            System.out.println("Existing release signing configuration prepared.");
        } catch (Exception error) {
            // Exception messages can contain paths or property values.
            System.err.println("Could not prepare local signing settings. Check the original key.properties file and Java installation.");
            System.exit(1);
        }
    }
}

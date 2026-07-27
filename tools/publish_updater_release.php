<?php

declare(strict_types=1);

const DEFAULT_CHANNEL = 'stable';
const RUNTIME_FILES = [
    'init.lua',
    'meta.lua',
    'config.ini',
    'cacert.pem',
    'otclientrc.lua',
];
const RUNTIME_DIRECTORIES = [
    'data',
    'modules',
    'mods',
];
const BINARY_CANDIDATES = [
    'WIN32-WGL' => ['OTClient.exe', 'otclient_x64.exe', 'otclient.exe'],
    'WIN32-EGL' => ['OTClient.exe', 'otclient_x64.exe', 'otclient.exe'],
    'WIN32-WGL-GCC' => ['OTClient.exe', 'otclient_x64.exe', 'otclient.exe'],
    'WIN32-EGL-GCC' => ['OTClient.exe', 'otclient_x64.exe', 'otclient.exe'],
    'X11-GLX' => ['otclient_linux', 'otclient'],
    'X11-EGL' => ['otclient_linux', 'otclient'],
    'MACOS' => [
        'OTClient.app/Contents/MacOS/OTClient',
        'OTClient.app/Contents/MacOS/otclient',
        'Contents/MacOS/OTClient',
        'Contents/MacOS/otclient',
        'OTClient',
    ],
    'ANDROID-EGL' => [],
    'ANDROID64-EGL' => [],
];
const PACKAGE_CANDIDATES = [
    'windows' => [
        'OTClient-windows-x64.zip',
        'otclient-windows-x64.zip',
    ],
    'linux' => [
        'OTClient-linux-x64.tar.gz',
        'OTClient-linux.tar.gz',
        'otclient-linux.tar.gz',
        'OTClient.AppImage',
        'otclient-linux-x64.AppImage',
    ],
    'macos' => [
        'OTClient-macos-arm64.dmg',
        'OTClient-macos-prod.dmg',
        'OTClient-macos.dmg',
        'OTClient.dmg',
        'OTClient-macos-arm64.zip',
        'OTClient-macos.zip',
        'OTClient.app.zip',
    ],
];

function usage(): void
{
    $script = basename(__FILE__);
    fwrite(STDERR, "Usage: php {$script} --source=/path/to/release [--target-root=/path/to/account-service/resources/client-updater] [--channel=stable] [--base-url=https://site/resources/client-updater]\n");
}

function normalizePath(string $path): string
{
    return rtrim($path, DIRECTORY_SEPARATOR);
}

function sanitizeChannel(string $channel): string
{
    $channel = trim($channel);
    if ($channel === '' || preg_match('/^[a-zA-Z0-9._-]+$/', $channel) !== 1) {
        throw new InvalidArgumentException('Invalid updater channel.');
    }

    return $channel;
}

function checksum(string $path): string
{
    $checksum = hash_file('crc32b', $path);
    if (!is_string($checksum) || $checksum === '') {
        throw new RuntimeException("Unable to hash file: {$path}");
    }

    $checksum = ltrim(strtolower($checksum), '0');
    return $checksum === '' ? '0' : $checksum;
}

function ensureDirectory(string $directory): void
{
    if (is_dir($directory)) {
        return;
    }

    if (!mkdir($directory, 0777, true) && !is_dir($directory)) {
        throw new RuntimeException("Unable to create directory: {$directory}");
    }
}

function removeDirectory(string $directory): void
{
    if (!is_dir($directory)) {
        return;
    }

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($directory, RecursiveDirectoryIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST
    );

    foreach ($iterator as $item) {
        $path = $item->getPathname();
        if ($item->isDir()) {
            if (!rmdir($path)) {
                throw new RuntimeException("Unable to remove directory: {$path}");
            }
            continue;
        }

        if (!unlink($path)) {
            throw new RuntimeException("Unable to remove file: {$path}");
        }
    }

    if (!rmdir($directory)) {
        throw new RuntimeException("Unable to remove directory: {$directory}");
    }
}

function copyFileToTarget(string $sourcePath, string $targetPath): void
{
    ensureDirectory(dirname($targetPath));
    if (!copy($sourcePath, $targetPath)) {
        throw new RuntimeException("Unable to copy {$sourcePath} to {$targetPath}");
    }
}

function collectBinaryFiles(string $sourceDir): array
{
    $binaries = [];

    foreach (BINARY_CANDIDATES as $platform => $candidates) {
        foreach ($candidates as $candidate) {
            $candidatePath = $sourceDir . DIRECTORY_SEPARATOR . $candidate;
            if (!is_file($candidatePath)) {
                continue;
            }

            $binaries[$platform] = $candidate;
            break;
        }
    }

    return $binaries;
}

function copyRuntimeFiles(string $sourceDir, string $targetFilesDir, array $binaryFiles): void
{
    foreach (RUNTIME_FILES as $fileName) {
        $sourcePath = $sourceDir . DIRECTORY_SEPARATOR . $fileName;
        if (!is_file($sourcePath)) {
            continue;
        }

        copyFileToTarget($sourcePath, $targetFilesDir . DIRECTORY_SEPARATOR . $fileName);
    }

    foreach (array_unique(array_values($binaryFiles)) as $binaryFile) {
        $sourcePath = $sourceDir . DIRECTORY_SEPARATOR . $binaryFile;
        if (!is_file($sourcePath)) {
            continue;
        }

        copyFileToTarget($sourcePath, $targetFilesDir . DIRECTORY_SEPARATOR . $binaryFile);
    }

    foreach (RUNTIME_DIRECTORIES as $directoryName) {
        $sourcePath = $sourceDir . DIRECTORY_SEPARATOR . $directoryName;
        if (!is_dir($sourcePath)) {
            continue;
        }

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($sourcePath, RecursiveDirectoryIterator::SKIP_DOTS)
        );

        foreach ($iterator as $item) {
            if (!$item->isFile()) {
                continue;
            }

            $itemPath = $item->getPathname();
            $relativePath = substr($itemPath, strlen($sourceDir));
            if (!is_string($relativePath) || $relativePath === '') {
                continue;
            }

            $relativePath = ltrim(str_replace(DIRECTORY_SEPARATOR, '/', $relativePath), '/');
            if (preg_match('/(^|\/)\./', $relativePath) === 1) {
                continue;
            }

            copyFileToTarget($itemPath, $targetFilesDir . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativePath));
        }
    }
}

function collectPackageFiles(string $sourceDir): array
{
    $searchRoots = array_values(array_unique([
        $sourceDir,
        dirname($sourceDir),
        dirname(dirname($sourceDir)),
    ]));
    $sourceBaseName = basename($sourceDir);
    $packages = [];

    foreach (PACKAGE_CANDIDATES as $packageKey => $candidateFiles) {
        $candidateNames = $candidateFiles;
        if ($packageKey === 'windows') {
            array_unshift($candidateNames, $sourceBaseName . '.zip');
        }

        foreach ($searchRoots as $searchRoot) {
            foreach ($candidateNames as $candidateName) {
                $candidatePath = normalizePath($searchRoot) . DIRECTORY_SEPARATOR . $candidateName;
                if (!is_file($candidatePath)) {
                    continue;
                }

                $packages[$packageKey] = [
                    'sourcePath' => $candidatePath,
                    'targetName' => basename($candidatePath),
                ];
                continue 3;
            }
        }
    }

    return $packages;
}

function copyPackageFiles(string $targetPackagesDir, array $packageFiles): void
{
    foreach ($packageFiles as $packageFile) {
        copyFileToTarget($packageFile['sourcePath'], $targetPackagesDir . DIRECTORY_SEPARATOR . $packageFile['targetName']);
    }
}

function buildManifest(string $targetFilesDir, string $filesUrl, string $channel, array $binaryFiles, string $packagesUrl, string $targetPackagesDir, array $packageFiles): array
{
    $files = [];
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($targetFilesDir, RecursiveDirectoryIterator::SKIP_DOTS)
    );

    foreach ($iterator as $item) {
        if (!$item->isFile()) {
            continue;
        }

        $pathName = $item->getPathname();
        $relativePath = substr($pathName, strlen($targetFilesDir));
        if (!is_string($relativePath) || $relativePath === '') {
            continue;
        }

        $relativePath = str_replace(DIRECTORY_SEPARATOR, '/', $relativePath);
        if (preg_match('/(^|\/)\./', $relativePath) === 1) {
            continue;
        }

        $files[$relativePath] = checksum($pathName);
    }

    ksort($files);

    $binaries = [];
    foreach ($binaryFiles as $platform => $binaryFile) {
        $relativePath = '/' . ltrim(str_replace(DIRECTORY_SEPARATOR, '/', $binaryFile), '/');
        if (!isset($files[$relativePath])) {
            continue;
        }

        $binaries[$platform] = [
            'file' => $relativePath,
            'checksum' => $files[$relativePath],
        ];
    }

    $packages = [];
    foreach ($packageFiles as $packageKey => $packageFile) {
        $packagePath = $targetPackagesDir . DIRECTORY_SEPARATOR . $packageFile['targetName'];
        if (!is_file($packagePath)) {
            continue;
        }

        $packages[$packageKey] = [
            'file' => $packageFile['targetName'],
            'url' => rtrim($packagesUrl, '/') . '/' . rawurlencode($packageFile['targetName']),
            'checksum' => checksum($packagePath),
            'size' => filesize($packagePath) ?: 0,
        ];
    }

    return [
        'channel' => $channel,
        'generatedAt' => gmdate('c'),
        'url' => rtrim($filesUrl, '/'),
        'files' => $files,
        'binaries' => $binaries,
        'packages' => $packages,
        'keepFiles' => false,
    ];
}

$options = getopt('', ['source:', 'target-root::', 'channel::', 'base-url::']);
$sourceDir = normalizePath((string) ($options['source'] ?? ''));
if ($sourceDir === '' || !is_dir($sourceDir)) {
    usage();
    throw new InvalidArgumentException('A valid --source directory is required.');
}

$projectRoot = dirname(__DIR__, 3);
$targetRoot = normalizePath((string) ($options['target-root'] ?? ($projectRoot . '/account-service/resources/client-updater')));
$channel = sanitizeChannel((string) ($options['channel'] ?? DEFAULT_CHANNEL));
$baseUrl = rtrim((string) ($options['base-url'] ?? 'https://astarot.online/resources/client-updater'), '/');
$channelRoot = $targetRoot . DIRECTORY_SEPARATOR . $channel;
$targetFilesDir = $channelRoot . DIRECTORY_SEPARATOR . 'files';
$targetPackagesDir = $channelRoot . DIRECTORY_SEPARATOR . 'packages';
$manifestPath = $channelRoot . DIRECTORY_SEPARATOR . 'manifest.json';
$filesUrl = $baseUrl . '/' . rawurlencode($channel) . '/files';
$packagesUrl = $baseUrl . '/' . rawurlencode($channel) . '/packages';

$binaryFiles = collectBinaryFiles($sourceDir);
$packageFiles = collectPackageFiles($sourceDir);

removeDirectory($targetFilesDir);
removeDirectory($targetPackagesDir);
ensureDirectory($targetFilesDir);
ensureDirectory($targetPackagesDir);
copyRuntimeFiles($sourceDir, $targetFilesDir, $binaryFiles);
copyPackageFiles($targetPackagesDir, $packageFiles);

$manifest = buildManifest($targetFilesDir, $filesUrl, $channel, $binaryFiles, $packagesUrl, $targetPackagesDir, $packageFiles);
$manifestJson = json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
if (!is_string($manifestJson)) {
    throw new RuntimeException('Unable to encode manifest JSON.');
}

ensureDirectory($channelRoot);
if (file_put_contents($manifestPath, $manifestJson . PHP_EOL) === false) {
    throw new RuntimeException("Unable to write manifest: {$manifestPath}");
}

fwrite(STDOUT, "Updater release published\n");
fwrite(STDOUT, "Source: {$sourceDir}\n");
fwrite(STDOUT, "Target: {$channelRoot}\n");
fwrite(STDOUT, "Files: " . count($manifest['files']) . "\n");
fwrite(STDOUT, "Binaries: " . count($manifest['binaries']) . "\n");
fwrite(STDOUT, "Packages: " . count($manifest['packages']) . "\n");

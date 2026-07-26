<?php

declare(strict_types=1);

function sendError(string $error): void
{
    echo json_encode(['error' => $error]);
    exit;
}

$filesDir = getenv('OTCLIENT_FILES_DIR');
if ($filesDir === false || $filesDir === '') {
    $filesDir = realpath(__DIR__ . '/../../files');
}

$filesUrl = getenv('OTCLIENT_FILES_URL');
if ($filesUrl === false || $filesUrl === '') {
    $filesUrl = 'https://astarot.online/files';
}

if ($filesDir === false || $filesDir === null || $filesDir === '') {
    sendError('Files directory is not configured.');
}

$filesAndDirs = ['init.lua', 'data', 'modules', 'mods'];
$checksumFile = 'checksums.txt';
$checksumUpdateInterval = 60;
$binaries = [
    'WIN32-WGL' => 'otclient_x64.exe',
    'WIN32-EGL' => 'otclient_x64.exe',
    'WIN32-WGL-GCC' => 'otclient_x64.exe',
    'WIN32-EGL-GCC' => 'otclient_x64.exe',
    'X11-GLX' => 'otclient_linux',
    'X11-EGL' => 'otclient_linux',
    'ANDROID-EGL' => '',
    'ANDROID64-EGL' => '',
];

$rawInput = file_get_contents('php://input');
$data = json_decode($rawInput ?: '[]', true) ?: [];

$version = $data['version'] ?? 0;
$build = $data['build'] ?? '';
$os = $data['os'] ?? 'unknown';
$platform = $data['platform'] ?? '';
$args = $data['args'] ?? [];
$binary = $binaries[$platform] ?? '';

$cacheFile = sys_get_temp_dir() . DIRECTORY_SEPARATOR . $checksumFile;
$cache = null;
if (file_exists($cacheFile) && (filemtime($cacheFile) + $checksumUpdateInterval > time())) {
    $cache = json_decode((string) file_get_contents($cacheFile), true);
}

if (!$cache) {
    $dir = realpath($filesDir);
    if ($dir === false) {
        sendError('Files directory not found.');
    }

    $rii = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir));
    $cache = [];
    foreach ($rii as $file) {
        if (!$file->isFile()) {
            continue;
        }

        $path = str_replace($dir, '', $file->getPathname());
        $path = str_replace(DIRECTORY_SEPARATOR, '/', $path);
        $checksum = hash_file('crc32b', $file->getPathname());
        if ($checksum !== false && $checksum !== '') {
            $parsedChecksum = ltrim($checksum, '0');
            $cache[$path] = $parsedChecksum === '' ? '0' : $parsedChecksum;
        }
    }

    file_put_contents($cacheFile . '.tmp', json_encode($cache));
    rename($cacheFile . '.tmp', $cacheFile);
}

$ret = [
    'url' => $filesUrl,
    'files' => [],
    'keepFiles' => false,
];

foreach ($cache as $file => $checksum) {
    $parts = explode('/', ltrim($file, '/'));
    $base = trim($parts[0] ?? '');

    if (in_array($base, $filesAndDirs, true)) {
        $ret['files'][$file] = $checksum;
    }

    if ($base === $binary && $binary !== '') {
        $ret['binary'] = [
            'file' => $file,
            'checksum' => $checksum,
        ];
    }
}

$body = json_encode($ret, JSON_PRETTY_PRINT);
header('Content-Length: ' . strlen($body));
echo $body;

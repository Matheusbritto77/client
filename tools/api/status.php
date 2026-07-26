<?php

declare(strict_types=1);

const AAC_BASE_URL = 'https://astarot.online';
const AAC_LOGIN_URL = AAC_BASE_URL . '/api/v1/login';

function postJson(string $url, array $payload): ?array
{
    $body = json_encode($payload);
    if ($body === false) {
        return null;
    }

    $response = false;
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $body,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 5,
            CURLOPT_TIMEOUT => 10,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'Accept: application/json',
            ],
        ]);
        $response = curl_exec($ch);
        curl_close($ch);
    } else {
        $context = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => "Content-Type: application/json\r\nAccept: application/json\r\n",
                'content' => $body,
                'timeout' => 10,
            ],
        ]);
        $response = file_get_contents($url, false, $context);
    }

    if ($response === false || $response === '' || $response === null) {
        return null;
    }

    $decoded = json_decode($response, true);
    return is_array($decoded) ? $decoded : null;
}

function brandedStatusResponse(array $cacheInfo, array $boostedData): array
{
    return [
        'playersonline' => (string) ($cacheInfo['playersonline'] ?? 0),
        'discord_online' => (int) ($cacheInfo['discord_online'] ?? 0),
        'discord_link' => AAC_BASE_URL,
        'youtube_link' => AAC_BASE_URL,
        'gamingyoutubestreams' => (string) ($cacheInfo['gamingyoutubestreams'] ?? 0),
        'gamingyoutubeviewer' => (string) ($cacheInfo['gamingyoutubeviewer'] ?? 0),
        'test' => 'cacheinfo',
        'boostedcreature' => $boostedData,
    ];
}

$rawInput = file_get_contents('php://input');
$data = json_decode($rawInput ?: '[]');
$requestType = is_object($data) && isset($data->type) ? (string) $data->type : '';

if ($requestType === 'cacheinfo') {
    $cacheInfo = postJson(AAC_LOGIN_URL, ['type' => 'cacheinfo']) ?? [];
    $boostedData = postJson(AAC_LOGIN_URL, ['type' => 'boostedcreature']) ?? [];

    echo json_encode(brandedStatusResponse($cacheInfo, $boostedData));
    exit;
}

if ($requestType === 'eventschedule') {
    $response = postJson(AAC_LOGIN_URL, ['type' => 'eventschedule']);
    if ($response === null) {
        $response = [
            'lastupdatetimestamp' => time(),
            'eventlist' => [],
        ];
    }

    echo json_encode($response);
    exit;
}

if ($requestType === 'showoff') {
    echo json_encode([
        'image' => AAC_BASE_URL . '/resources/base/logo.png',
        'title' => 'astarOT',
        'description' => 'Cliente oficial do astarOT, com acesso travado ao seu mundo, status online integrado e boosted sincronizado com o AAC.',
    ]);
    exit;
}

if ($requestType === 'boostedcreature') {
    $response = postJson(AAC_LOGIN_URL, ['type' => 'boostedcreature']);
    if ($response === null) {
        $response = [
            'creatureraceid' => 32,
            'bossraceid' => 300,
            'creaturename' => '',
            'creaturelooktype' => 0,
            'creaturelookhead' => 0,
            'creaturelookbody' => 0,
            'creaturelooklegs' => 0,
            'creaturelookfeet' => 0,
            'creaturelookaddons' => 0,
            'creaturelookmount' => 0,
            'creatureimageurl' => '',
            'bossname' => '',
            'bosslooktype' => 0,
            'bosslookhead' => 0,
            'bosslookbody' => 0,
            'bosslooklegs' => 0,
            'bosslookfeet' => 0,
            'bosslookaddons' => 0,
            'bosslookmount' => 0,
            'bossimageurl' => '',
        ];
    }

    echo json_encode($response);
    exit;
}

http_response_code(404);
echo json_encode([
    'error' => 'Unsupported request type',
]);

<?php

declare(strict_types=1);

namespace Ondewo\S2t\Tests\Generated;

use Ondewo\S2t\InferenceBackend;
use Ondewo\S2t\ListS2tPipelinesRequest;
use Ondewo\S2t\OpenaiLlmOptions;
use Ondewo\S2t\S2tInference;
use Ondewo\S2t\TranscribeFileRequest;
use Ondewo\S2t\TranscribeFileResponse;
use Ondewo\S2t\TranscribeRequestConfig;
use Ondewo\S2t\Transcription;
use Ondewo\S2t\TranscriptionReturnOptions;
use Ondewo\S2t\WordDetail;
use PHPUnit\Framework\TestCase;
use UnexpectedValueException;

/**
 * Wire-level exercise of the generated messages. These are the assertions that catch a broken
 * generator: a field that is declared but never written, a presence field that silently drops its
 * zero value, an enum whose zero constant moved.
 *
 * PRODUCT-SPECIFIC: the message and enum names below come from ondewo-s2t-api.
 */
final class MessageSerializationTest extends TestCase
{
    public function testAMessageSurvivesABinaryRoundTrip(): void
    {
        // Every float literal here is exactly representable in the 32-bit `float` the protos
        // declare, so the round trip is lossless and assertSame() on a float is legitimate.
        $word = new WordDetail();
        $word->setStartTime(0.5);
        $word->setEndTime(1.25);
        $word->setWord('hallo');
        $word->setConfidence(0.75);

        $transcription = new Transcription();
        $transcription->setTranscription('hallo welt');
        $transcription->setConfidenceScore(0.875);
        $transcription->setWords([$word]);

        $response = new TranscribeFileResponse();
        $response->setTranscriptions([$transcription]);
        $response->setTime(2.5);
        $response->setAudioUuid('6b2c8e5a-audio');

        $bytes = $response->serializeToString();
        self::assertNotSame('', $bytes, 'a populated message serialised to zero bytes');

        $parsed = new TranscribeFileResponse();
        $parsed->mergeFromString($bytes);

        self::assertSame(2.5, $parsed->getTime());
        self::assertSame('6b2c8e5a-audio', $parsed->getAudioUuid());

        $parsedTranscriptions = iterator_to_array($parsed->getTranscriptions());
        self::assertCount(1, $parsedTranscriptions);
        self::assertSame('hallo welt', $parsedTranscriptions[0]->getTranscription());
        self::assertSame(0.875, $parsedTranscriptions[0]->getConfidenceScore());

        $parsedWords = iterator_to_array($parsedTranscriptions[0]->getWords());
        self::assertCount(1, $parsedWords);
        self::assertSame('hallo', $parsedWords[0]->getWord());
        self::assertSame(0.5, $parsedWords[0]->getStartTime());
        self::assertSame(1.25, $parsedWords[0]->getEndTime());
        self::assertSame(0.75, $parsedWords[0]->getConfidence());

        // Byte-for-byte stability, which field-by-field getters alone would not prove.
        self::assertSame($bytes, $parsed->serializeToString());
    }

    public function testAnUnsetSubMessageStaysUnset(): void
    {
        $request = new TranscribeFileRequest();
        $request->setAudioFile("RIFF\x00\x01\x02WAVE");

        self::assertFalse($request->hasConfig());
        self::assertNull($request->getConfig());

        $config = new TranscribeRequestConfig();
        $config->setS2TPipelineId('default_de');
        $request->setConfig($config);
        self::assertTrue($request->hasConfig());
        self::assertSame('default_de', $request->getConfig()->getS2TPipelineId());

        $request->clearConfig();
        self::assertFalse($request->hasConfig());

        // The bytes field is binary-safe: it must survive a round trip unchanged.
        $parsed = new TranscribeFileRequest();
        $parsed->mergeFromString($request->serializeToString());
        self::assertSame("RIFF\x00\x01\x02WAVE", $parsed->getAudioFile());
    }

    public function testAProto3OptionalFieldKeepsItsZeroValueOnTheWire(): void
    {
        // The failure this guards against is the one that bit the Angular target: an explicit
        // presence field whose ZERO value is indistinguishable from "unset" and is therefore
        // never written, so a client cannot clear a string or send `0`.
        $options = new OpenaiLlmOptions();
        $options->setModel('gpt-4o-transcribe');
        $options->setApiKey('');
        $options->setMaxTokens(0);
        $options->setStore(false);

        self::assertTrue($options->hasApiKey());
        self::assertTrue($options->hasMaxTokens());
        self::assertTrue($options->hasStore());

        $parsed = new OpenaiLlmOptions();
        $parsed->mergeFromString($options->serializeToString());

        self::assertTrue($parsed->hasApiKey(), 'an explicitly set empty string was dropped on the wire');
        self::assertSame('', $parsed->getApiKey());
        self::assertTrue($parsed->hasMaxTokens(), 'an explicitly set 0 was dropped on the wire');
        self::assertSame(0, $parsed->getMaxTokens());
        self::assertTrue($parsed->hasStore(), 'an explicitly set false was dropped on the wire');
        self::assertFalse($parsed->getStore());

        // ... and an untouched presence field must stay absent.
        $untouched = new OpenaiLlmOptions();
        self::assertFalse($untouched->hasApiKey());
        $reparsed = new OpenaiLlmOptions();
        $reparsed->mergeFromString($untouched->serializeToString());
        self::assertFalse($reparsed->hasApiKey());
    }

    public function testAMessageSurvivesAJsonRoundTrip(): void
    {
        $request = new ListS2tPipelinesRequest();
        $request->setLanguages(['de', 'en']);
        $request->setDomains(['medical']);
        $request->setRegisteredOnly(true);

        $json = $request->serializeToJsonString();
        self::assertJson($json);

        $parsed = new ListS2tPipelinesRequest();
        $parsed->mergeFromJsonString($json);

        self::assertSame(['de', 'en'], iterator_to_array($parsed->getLanguages()));
        self::assertSame(['medical'], iterator_to_array($parsed->getDomains()));
        self::assertTrue($parsed->getRegisteredOnly());
    }

    public function testAnIntegerFieldSurvivesAJsonRoundTrip(): void
    {
        // Its own case because google/protobuf's PURE-PHP JSON parser range-checks every integer
        // with bccomp(): without ext-bcmath this dies with "Call to undefined function
        // Google\Protobuf\Internal\bccomp()" on the first int field it meets. The extension is a
        // `suggest` of google/protobuf, not a `require`, so nothing else would surface that.
        $options = new TranscriptionReturnOptions();
        $options->setReturnAlternativeTranscriptions(true);
        $options->setReturnAlternativeTranscriptionsNr(3);
        $options->setReturnAlternativeWordsNr(0);

        $parsed = new TranscriptionReturnOptions();
        $parsed->mergeFromJsonString($options->serializeToJsonString());

        self::assertTrue($parsed->getReturnAlternativeTranscriptions());
        self::assertSame(3, $parsed->getReturnAlternativeTranscriptionsNr());
        self::assertSame(0, $parsed->getReturnAlternativeWordsNr());
    }

    public function testTheEnumZeroValueIsTheUnknownMember(): void
    {
        self::assertSame(0, InferenceBackend::INFERENCE_BACKEND_UNKNOWN);
        self::assertSame(
            'INFERENCE_BACKEND_UNKNOWN',
            InferenceBackend::name(InferenceBackend::INFERENCE_BACKEND_UNKNOWN)
        );
        self::assertSame(InferenceBackend::INFERENCE_BACKEND_FLAX, InferenceBackend::value('INFERENCE_BACKEND_FLAX'));

        // The zero value must be requestable, i.e. it must be the DEFAULT of a field typed by it.
        self::assertSame(InferenceBackend::INFERENCE_BACKEND_UNKNOWN, (new S2tInference())->getInferenceBackend());
    }

    public function testAnUnknownEnumMemberIsRejected(): void
    {
        $this->expectException(UnexpectedValueException::class);

        InferenceBackend::name(4242);
    }
}

<?php
// GENERATED CODE -- DO NOT EDIT!

// Original file comments:
// Copyright 2023 ONDEWO GmbH
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.https://ondewo.slack.com/archives/CAWPP61NY
//
namespace Ondewo\S2t;

/**
 * <p>Speech-to-text service</p>
 */
class Speech2TextClient extends \Grpc\BaseStub {

    /**
     * @param string $hostname hostname
     * @param array $opts channel options
     * @param \Grpc\Channel $channel (optional) re-use channel object
     */
    public function __construct($hostname, $opts, $channel = null) {
        parent::__construct($hostname, $opts, $channel);
    }

    /**
     * <p>Transcribes an audio file</p>
     * @param \Ondewo\S2t\TranscribeFileRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function TranscribeFile(\Ondewo\S2t\TranscribeFileRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/TranscribeFile',
        $argument,
        ['\Ondewo\S2t\TranscribeFileResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Transcribes an audio stream.</p>
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\BidiStreamingCall
     */
    public function TranscribeStream($metadata = [], $options = []) {
        return $this->_bidiRequest('/ondewo.s2t.Speech2Text/TranscribeStream',
        ['\Ondewo\S2t\TranscribeStreamResponse','decode'],
        $metadata, $options);
    }

    /**
     * <p>Gets a speech to text pipeline corresponding to the id specified in <code>S2tPipelineId</code>. If no corresponding id is
     * found, raises <code>ModuleNotFoundError</code> in server.</p>
     * @param \Ondewo\S2t\S2tPipelineId $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function GetS2tPipeline(\Ondewo\S2t\S2tPipelineId $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/GetS2tPipeline',
        $argument,
        ['\Ondewo\S2t\Speech2TextConfig', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Creates a new speech to text pipeline from a <code>Speech2TextConfig</code> and registers the new pipeline in the server.</p>
     * @param \Ondewo\S2t\Speech2TextConfig $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function CreateS2tPipeline(\Ondewo\S2t\Speech2TextConfig $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/CreateS2tPipeline',
        $argument,
        ['\Ondewo\S2t\S2tPipelineId', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Deletes a pipeline corresponding to the id parsed in <code>S2tPipelineId</code>. If no corresponding id is
     * found, raises <code>ModuleNotFoundError</code> in server.</p>
     * @param \Ondewo\S2t\S2tPipelineId $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function DeleteS2tPipeline(\Ondewo\S2t\S2tPipelineId $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/DeleteS2tPipeline',
        $argument,
        ['\Google\Protobuf\GPBEmpty', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Updates a pipeline with the id specified in <code>Speech2TextConfig</code> with the new config. If no corresponding id is
     * found, raises <code>ModuleNotFoundError</code> in server.</p>
     * @param \Ondewo\S2t\Speech2TextConfig $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function UpdateS2tPipeline(\Ondewo\S2t\Speech2TextConfig $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/UpdateS2tPipeline',
        $argument,
        ['\Google\Protobuf\GPBEmpty', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Lists all speech to text pipelines.</p>
     * @param \Ondewo\S2t\ListS2tPipelinesRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function ListS2tPipelines(\Ondewo\S2t\ListS2tPipelinesRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/ListS2tPipelines',
        $argument,
        ['\Ondewo\S2t\ListS2tPipelinesResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Returns a message containing a list of all languages for which there exist pipelines.</p>
     * @param \Ondewo\S2t\ListS2tLanguagesRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function ListS2tLanguages(\Ondewo\S2t\ListS2tLanguagesRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/ListS2tLanguages',
        $argument,
        ['\Ondewo\S2t\ListS2tLanguagesResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Returns a message containing a list of all domains for which there exist pipelines.</p>
     * @param \Ondewo\S2t\ListS2tDomainsRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function ListS2tDomains(\Ondewo\S2t\ListS2tDomainsRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/ListS2tDomains',
        $argument,
        ['\Ondewo\S2t\ListS2tDomainsResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Returns a message containing the version of the running speech to text server.</p>
     * @param \Google\Protobuf\GPBEmpty $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function GetServiceInfo(\Google\Protobuf\GPBEmpty $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/GetServiceInfo',
        $argument,
        ['\Ondewo\S2t\S2tGetServiceInfoResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Given a list of pipeline ids, returns a list of <code>LanguageModelPipelineId</code> messages containing the pipeline
     * id and a list of the language models loaded in the pipeline.</p>
     * @param \Ondewo\S2t\ListS2tLanguageModelsRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function ListS2tLanguageModels(\Ondewo\S2t\ListS2tLanguageModelsRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/ListS2tLanguageModels',
        $argument,
        ['\Ondewo\S2t\ListS2tLanguageModelsResponse', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Create a user language model.</p>
     * @param \Ondewo\S2t\CreateUserLanguageModelRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function CreateUserLanguageModel(\Ondewo\S2t\CreateUserLanguageModelRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/CreateUserLanguageModel',
        $argument,
        ['\Google\Protobuf\GPBEmpty', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Delete a user language model.</p>
     * @param \Ondewo\S2t\DeleteUserLanguageModelRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function DeleteUserLanguageModel(\Ondewo\S2t\DeleteUserLanguageModelRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/DeleteUserLanguageModel',
        $argument,
        ['\Google\Protobuf\GPBEmpty', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Add data to a user language model.</p>
     * @param \Ondewo\S2t\AddDataToUserLanguageModelRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function AddDataToUserLanguageModel(\Ondewo\S2t\AddDataToUserLanguageModelRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/AddDataToUserLanguageModel',
        $argument,
        ['\Google\Protobuf\GPBEmpty', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Train a user language model.</p>
     * @param \Ondewo\S2t\TrainUserLanguageModelRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function TrainUserLanguageModel(\Ondewo\S2t\TrainUserLanguageModelRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/TrainUserLanguageModel',
        $argument,
        ['\Google\Protobuf\GPBEmpty', 'decode'],
        $metadata, $options);
    }

    /**
     * <p>Retrieves a list of normalization pipelines based on specific requirements.</p>
     * @param \Ondewo\S2t\ListS2tNormalizationPipelinesRequest $argument input argument
     * @param array $metadata metadata
     * @param array $options call options
     * @return \Grpc\UnaryCall
     */
    public function ListS2tNormalizationPipelines(\Ondewo\S2t\ListS2tNormalizationPipelinesRequest $argument,
      $metadata = [], $options = []) {
        return $this->_simpleRequest('/ondewo.s2t.Speech2Text/ListS2tNormalizationPipelines',
        $argument,
        ['\Ondewo\S2t\ListS2tNormalizationPipelinesResponse', 'decode'],
        $metadata, $options);
    }

}

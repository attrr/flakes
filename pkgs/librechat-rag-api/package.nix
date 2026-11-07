{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  pandoc,
  nltk-data,
}:

let
  # requirements.lite.txt, minus sentence_transformers/huggingface of the full image
  python = python3.withPackages (
    ps: with ps; [
      langchain
      langchain-community
      langchain-openai
      langchain-core
      langchain-google-genai
      langchain-text-splitters
      langchain-mongodb
      langchain-aws
      langchain-ollama
      sqlalchemy
      python-dotenv
      fastapi
      psycopg2
      pgvector
      uvicorn
      pypdf
      unstructured
      markdown
      networkx
      pandas
      openpyxl
      docx2txt
      pypandoc
      pyjwt
      asyncpg
      python-multipart
      aiofiles
      rapidocr-onnxruntime
      opencv4
      pymongo
      cryptography
      python-magic
      python-pptx
      xlrd
      boto3
      chardet
      tenacity
      msoffcrypto-tool
    ]
  );

  # what Dockerfile.lite downloads, so unstructured never fetches at runtime
  nltkData = lib.concatMapStringsSep ":" toString (
    with nltk-data;
    [
      punkt-tab
      averaged-perceptron-tagger
      averaged-perceptron-tagger-eng
    ]
  );
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "librechat-rag-api";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "danny-avila";
    repo = "rag_api";
    tag = "v${finalAttrs.version}";
    hash = "sha256-MBJx5MGnbflzxLx9T0c9zxJ7QqpbZJUFezMz158g48k=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/librechat-rag-api $out/bin
    cp -r app utils main.py $out/share/librechat-rag-api/

    # uvicorn's cli rather than main.py, which hardcodes host/port: --uds, --fd
    makeWrapper ${lib.getExe python} $out/bin/librechat-rag-api \
      --add-flags "-m uvicorn --app-dir $out/share/librechat-rag-api main:app" \
      --prefix PATH : ${lib.makeBinPath [ pandoc ]} \
      --set-default NLTK_DATA ${nltkData} \
      --set-default SCARF_NO_ANALYTICS true \
      --set-default DO_NOT_TRACK true

    runHook postInstall
  '';

  meta = {
    description = "ID-based RAG FastAPI, LibreChat's file search backend";
    homepage = "https://github.com/danny-avila/rag_api";
    license = lib.licenses.mit;
    mainProgram = "librechat-rag-api";
  };
})

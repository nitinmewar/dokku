#!/usr/bin/env bats
load test_helper

setup_file() {
  if ! command -v "pack" &>/dev/null; then
    add-apt-repository --yes ppa:cncf-buildpacks/pack-cli
    apt-get update
    apt-get --yes install pack-cli
  fi
}

setup() {
  global_setup
  create_app
}

teardown() {
  destroy_app
  global_teardown
}

@test "(app-json) app.json scripts" {
  run deploy_app python
  echo "output: $output"
  echo "status: $status"
  assert_success

  run docker inspect "${TEST_APP}.web.1" --format "{{json .Config.Cmd}}"
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output '["/start","web"]'

  run /bin/bash -c "dokku --rm run $TEST_APP ls /app/prebuild.test"
  echo "output: $output"
  echo "status: $status"
  assert_failure

  run /bin/bash -c "dokku --rm run $TEST_APP ls /app/predeploy.test"
  echo "output: $output"
  echo "status: $status"
  assert_success

  CID=$(docker ps -a -q  -f "ancestor=dokku/${TEST_APP}" -f "label=dokku_phase_script=postdeploy")
  DOCKER_COMMIT_LABEL_ARGS=("--change" "LABEL org.label-schema.schema-version=1.0" "--change" "LABEL org.label-schema.vendor=dokku" "--change" "LABEL com.dokku.app-name=$TEST_APP")
  IMAGE_ID=$(docker commit "${DOCKER_COMMIT_LABEL_ARGS[@]}" $CID dokku-test/${TEST_APP})
  run /bin/bash -c "docker run --rm $IMAGE_ID ls /app/postdeploy.test"
  echo "output: $output"
  echo "status: $status"
  assert_success
}

@test "(app-json) app.json scripts postdeploy" {
  run deploy_app python dokku@dokku.me:$TEST_APP add_postdeploy_command
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output_contains "touch /app/heroku-postdeploy.test"
  assert_output_contains "python3 release.py"
}

@test "(app-json) app.json scripts missing" {
  run deploy_app nodejs-express-noappjson
  echo "output: $output"
  echo "status: $status"
  assert_success
}

@test "(app-json) app.json dockerfile cmd" {
  run deploy_app dockerfile-procfile
  echo "output: $output"
  echo "status: $status"
  assert_success

  run docker inspect "dokku/${TEST_APP}:latest" --format "{{json .Config.Cmd}}"
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output '["/bin/sh","-c","npm start"]'

  run docker inspect "dokku/${TEST_APP}:latest" --format "{{json .Config.Entrypoint}}"
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output 'null'
}

@test "(app-json) app.json dockerfile release" {
  run /bin/bash -c "dokku config:set --no-restart $TEST_APP SECRET_KEY=fjdkslafjdk ENVIRONMENT=dev DATABASE_URL=sqlite:///db.sqlite3"
  echo "output: $output"
  echo "status: $status"
  assert_success

  run deploy_app dockerfile-release
  echo "output: $output"
  echo "status: $status"
  assert_output_contains "Executing release task from Procfile"
  assert_output_contains "SECRET_KEY: fjdkslafjdk"
  assert_success
}

@test "(app-json) app.json dockerfile entrypoint release" {
  run deploy_app dockerfile-entrypoint dokku@dokku.me:$TEST_APP add_release_command
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output_contains "touch /app/release.test" 2
}

@test "(app-json) app.json dockerfile entrypoint predeploy" {
  run deploy_app dockerfile-entrypoint
  echo "output: $output"
  echo "status: $status"
  assert_output_contains "Executing predeploy task from app.json"
  assert_output_contains "entrypoint script started with arguments touch /app/predeploy.test"
  assert_success

  run /bin/bash -c "dokku --rm run $TEST_APP ls /app/predeploy.test"
  echo "output: $output"
  echo "status: $status"
  assert_success
}

@test "(app-json) app.json cnb release" {
  run /bin/bash -c "dokku config:set --no-restart $TEST_APP DOKKU_CNB_EXPERIMENTAL=1 SECRET_KEY=fjdkslafjdk"
  echo "output: $output"
  echo "status: $status"
  assert_success

  run deploy_app python dokku@dokku.me:$TEST_APP add_requirements_txt
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output_contains "Executing release task from Procfile"
  assert_output_contains "SECRET_KEY: fjdkslafjdk"

  run /bin/bash -c "curl $(dokku url $TEST_APP)/env"
  echo "output: $output"
  echo "status: $status"
  assert_success
  assert_output_contains '"SECRET_KEY": "fjdkslafjdk"'
}

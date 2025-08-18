while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "Line: [$line]"
done < <(echo -e "    [\"slack.rs\", 0, 1, \"Slack.rs Rust プロジェクト\"],\n    [\"hitomi\", 0, 1, \"hitomi プロジェクト\"]")

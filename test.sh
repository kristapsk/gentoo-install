. inc.config.sh

while read tool_line; do
    if [ "$tool_line" != "" ]; then
        if ! grep -qs "\[" <<< "$tool_line"; then
            tool="$tool_line"
        else
            tool="`echo "$tool_line" | sed "s/\[.*//"`"
            use_changes="`echo "$tool_line" | sed "s/.*\[//" | sed "s/\].*//" | tr ',' ' '`"
            echo -n "USE=\"$use_changes\" "
        fi
        echo $tool
    fi
done <<< "$SYSTEM_TOOLS"


function friday-forget --description 'Wipe Friday chat history'
    rm -f ~/.cache/friday_history.json && echo "Friday: Memory format complete."
end

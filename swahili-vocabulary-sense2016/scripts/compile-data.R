library(data.table)
library(purrr)
library(tidyr)



# Vocabulary materials ----------------------------------------------------

vocab_list <- fread(file.path("data", "vocab_list.csv"))

# Practice data -----------------------------------------------------------

d_practice_url <- "https://github.com/fsense/parameter-stability-paper/raw/master/data/MODEL_data.csv"
d_practice_raw <- fread(d_practice_url)

# Remove duplicates
# Some participants did a block more than once.
# In those cases we'll remove all the data from these participants.
duplicates <- d_practice_raw[, .N, by = .(subj, block, rep)][N > 1]
duplicates[, unique(subj)]
d_practice <- d_practice_raw[!subj %in% duplicates[, unique(subj)]]


# Fix rows with erroneous column shift
d_practice[, RT := as.numeric(RT)] |>
  suppressWarnings()
d_practice[, duration := as.double(duration)]
d_practice_shift <- d_practice[is.na(RT)][, RT := NULL]
setnames(d_practice_shift,
         old = colnames(d_practice_shift),
         new = c(colnames(d_practice_shift)[1:5], "RT", colnames(d_practice_shift)[6:15])
)
d_practice_shift[, estRT := NA]
d_practice_shift[, duration := as.double(duration)]
d_practice[is.na(RT)] <- d_practice_shift

# Vocabulary block order was randomised between participants.
d_blockorder_url <- "https://github.com/fsense/parameter-stability-paper/raw/master/data/data_for_Friederike.csv"
d_blockorder <- fread(d_blockorder_url)
d_blockorder <- d_blockorder[, .(session = session[1]), by  = .(subj, block)]

vocab_by_block <- d_practice[, .(answer = unique(tolower(resp[isCorrect == TRUE]))), by  = .(block, item)][vocab_list, on = .(answer)]
setorder(vocab_by_block, item)

d_practice_vocab <- d_practice[d_blockorder, on = .(subj, block)][block %in% c("vocab1", "vocab2", "vocab3")]
  
d_practice_vocab_clean <- vocab_by_block[d_practice_vocab, on = .(block, item)][,
  .(subj = as.factor(subj),
    session = as.factor(session),
    block = as.factor(block),
    trial = as.numeric(rep),
    time,
    item = as.factor(item),
    presentation,
    type = as.factor(type),
    cue,
    answer,
    response = resp,
    correct = isCorrect,
    rt = RT
  )
]

setorder(d_practice_vocab_clean, subj, session, block, time)

fwrite(d_practice_vocab_clean, file.path("data", "vocabulary_practice_data.csv"))




# Test data ---------------------------------------------------------------

d_test_urls <- c("https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_vocab1.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_vocab2.csv",
                 "https://github.com/fsense/parameter-stability-paper/raw/master/data/TEST_vocab.csv")

d_test <- map_dfr(d_test_urls, function(url) {
  d <- fread(url)
  d[, Timestamp := NULL]
  pivot_longer(d,
               cols = -c(1,27),
               names_to = "answer",
               values_to = "response")
})

setDT(d_test)


d_test[, correct := tolower(response) == answer]
d_test_clean <- d_test[vocab_by_block, on = .(block, answer)][,
                                                              .(subj = as.factor(subj),
                                                                block = as.factor(block),
                                                                item = as.factor(item),
                                                                cue,
                                                                answer,
                                                                response,
                                                                correct)
]

# Remove test data from participants with duplicate practice sessions
d_test_clean <- d_test_clean[!subj %in% duplicates[, unique(subj)]]

fwrite(d_test_clean, file.path("data", "vocabulary_test_data.csv"))
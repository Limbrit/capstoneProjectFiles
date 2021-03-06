# Data Loading and Preparation

#############################################################
# Create edx set, validation set, and submission file
#############################################################

# Note: this process could take a couple of minutes

options(scipen = 999)
if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
if(!require(ggplot2)) install.packages("ggplot2", repos = "http://cran.us.r-project.org")

# MovieLens 10M dataset:
# https://grouplens.org/datasets/movielens/10m/
# http://files.grouplens.org/datasets/movielens/ml-10m.zip

dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)

ratings <- read.table(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
                      col.names = c("userId", "movieId", "rating", "timestamp"))

movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")
movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(levels(movieId))[movieId],
                                           title = as.character(title),
                                           genres = as.character(genres))

movielens <- left_join(ratings, movies, by = "movieId")

# Validation set will be 10% of MovieLens data

set.seed(1)
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]

# Make sure userId and movieId in validation set are also in edx set

validation <- temp %>% 
  semi_join(edx, by = "movieId") %>%
  semi_join(edx, by = "userId")

# Add rows removed from validation set back into edx set

removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)

# Learners will develop their algorithms on the edx set
# For grading, learners will run algorithm on validation set to generate ratings

rm(dl, ratings, movies, test_index, temp, movielens, removed)

#################################################################################

# Top 6 Records
head(edx)
head(validation)

# Load required library
library(anytime)
library(data.table)
library(scales)
library(doParallel)
cl <- makeCluster(4)
registerDoParallel(cl)

# Time stamp as date factor
edx$timestamp<-anydate(edx$timestamp)
edx$date<-as.factor(format(edx$timestamp, "%Y-%m"))
edx$date<-as.factor(edx$date)

# Number of unique users that provided ratings and for how many unique movies they provided
edx %>% 
  summarize(n_users = n_distinct(userId),
            n_movies = n_distinct(movieId))

# Some movies get rated more than others, here is the distribution:
edx %>% 
  count(movieId) %>% 
  ggplot(aes(n)) + 
  geom_histogram(bins = 30, color = "black") + 
  scale_x_log10() + 
  ggtitle("Movies")

# Some users are more active than others at rating movies
edx %>% 
  count(userId) %>% 
  ggplot(aes(n)) + 
  geom_histogram(bins = 30, color = "black") + 
  scale_x_log10() + 
  ggtitle("Users")

# Rating Distribution
aa<-as.data.frame(edx %>%
                    group_by(rating) %>%
                    summarise (n = n()) %>%
                    mutate(percent = n / sum(n)))
aa$percent<-percent(aa$percent)
print(aa)

# Break out genre, use first three columns as factors, impute missing 
temp <- as.data.frame(edx$genres, stringsAsFactors=FALSE)
temp2 <- as.data.frame(tstrsplit(temp[,1], '[|]', type.convert=TRUE), stringsAsFactors=FALSE)
colnames(temp2) <- c(1:7)
rm(temp)
temp2[,4:8] <- NULL
temp2 <- as.data.frame(lapply(temp2, factor))

# Impute with mode per column
imp <- names(sort(table(temp2[,2]),decreasing=TRUE)[1])
temp2[,2][is.na(temp2[,2])] <- imp 
imp1<-names(sort(table(temp2[,3]),decreasing=TRUE)[1])
temp2[,3][is.na(temp2[,3])] <- imp1
temp2[,1][temp2[,1] == "(no genres listed)"] <- "Action"
temp2[,1]<-as.factor(temp2[,1])

# cbind to edx
edx1<-cbind(edx, temp2)

# Visualization of Rating across Genere
N<-ggplot(edx1) + geom_bar(aes(x = rating))
N + theme(axis.text.x = element_text(angle = 60, hjust = 1)) +theme(plot.title = element_text(hjust = 0.5))+ ggtitle("Count of Ratings for all Catagories") + xlab("Rating Catagory") + ylab("Number of Ratings")

p <- ggplot(edx1, aes(x=edx1$`X1`, y=as.numeric(edx1$rating)/2)) + stat_summary(fun.y="mean", geom="bar")
p + theme(axis.text.x = element_text(angle = 60, hjust = 1)) +theme(plot.title = element_text(hjust = 0.5))+ ggtitle("Average User Rating by Genre-First Catagory") + xlab("Genre") + ylab("Average User Rating")

q <- ggplot(edx1, aes(x=edx1$`X2`, y=as.numeric(edx1$rating)/2)) + stat_summary(fun.y="mean", geom="bar")
q + theme(axis.text.x = element_text(angle = 60, hjust = 1)) +theme(plot.title = element_text(hjust = 0.5))+ ggtitle("Average User Rating by Genre-Second Catagory") + xlab("Genre") + ylab("Average User Rating")

r <- ggplot(edx1, aes(x=edx1$`X3`, y=as.numeric(edx1$rating)/2)) + stat_summary(fun.y="mean", geom="bar")
r + theme(axis.text.x = element_text(angle = 60, hjust = 1)) +theme(plot.title = element_text(hjust = 0.5))+ ggtitle("Average User Rating by Genre-Third Catagory") + xlab("Genre") + ylab("Average User Rating")
rm(N, p, q, r, edx1, aa, cl, temp2, imp, imp1)

# Training and Testing
# Define test and train datasets using edx. 80% sample for training, and 20% sample for testing.

set.seed(1)
train_index <- createDataPartition(y = edx$rating, times = 1, p = 0.8, list = FALSE)
train_set <- edx[train_index, ]
temp <- edx[-train_index, ]

# Make sure userId and movieId in test set are also in train set
test_set <- temp %>% 
  semi_join(train_set, by = "movieId") %>%
  semi_join(train_set, by = "userId")

# Add rows removed from test set back into train set

removed <- anti_join(temp, test_set)
train_set <- rbind(train_set, removed)

rm(temp, removed) # remove temporary datasets

# Recommendation systems : we will use three approaches

# RMSE Calculations
RMSE <- function(true_ratings, predicted_ratings){
  sqrt(mean((true_ratings - predicted_ratings)^2))
}

# 1st model : we predict the same rating for all movies regardless of user
mu_hat <- mean(train_set$rating)
mu_hat
model_1_rmse <- RMSE(test_set$rating, mu_hat)
model_1_rmse

# As we go along, we will be comparing different approaches. 
# Let's start by creating a results table with this naive approach :
rmse_results <- data_frame(method = "Just the average", RMSE = model_1_rmse)
rmse_results%>%knitr::kable()

# 2nd model : Modeling movie effects
# fit <- lm(rating ~ as.factor(userId), data = movielens)
# the lm() function will be very slow here because there are thousands of bias, each movie gets one
# we will use instead the least square estimate

mu <- mean(train_set$rating) 
movie_avgs <- train_set %>% 
  group_by(movieId) %>% 
  summarize(b_i = mean(rating - mu))

# These estimates vary substantially
movie_avgs %>% qplot(b_i, geom ="histogram", bins = 10, data = ., color = I("black"))

# Let's see how much the RMSE improves with this 2nd model
predicted_ratings <- mu + test_set %>% 
  left_join(movie_avgs, by='movieId') %>%
  .$b_i

model_2_rmse <- RMSE(predicted_ratings, test_set$rating)
rmse_results <- bind_rows(rmse_results,
                          data_frame(method="Movie Effect Model",  
                                     RMSE = model_2_rmse ))
rmse_results %>% knitr::kable()

# 3rd model : User effects
# Let's compute the average rating for user u for those that have rated over 100 movies.
# Notice that there is substantial variability across users as well: 
# Some users are very cranky and others love every movie.

train_set %>% 
  group_by(userId) %>% 
  summarize(b_u = mean(rating)) %>% 
  filter(n()>=100) %>%
  ggplot(aes(b_u)) + 
  geom_histogram(bins = 30, color = "black")

# User-specific effect model : lm(rating ~ as.factor(movieId) + as.factor(userId))
# We will compute an approximation instead for the reasons described earlier in 2nd model

user_avgs <- test_set %>% 
  left_join(movie_avgs, by='movieId') %>%
  group_by(userId) %>%
  summarize(b_u = mean(rating - mu - b_i))

# We can now construct predictors and see how much the RMSE improves
predicted_ratings <- test_set %>% 
  left_join(movie_avgs, by='movieId') %>%
  left_join(user_avgs, by='userId') %>%
  mutate(pred = mu + b_i + b_u) %>%
  .$pred

model_3_rmse <- RMSE(predicted_ratings, test_set$rating)
rmse_results <- bind_rows(rmse_results,
                          data_frame(method="Movie + User Effects Model",  
                                     RMSE = model_3_rmse ))

# Results : the 3rd model has the lowest RMSE and will be used for final testing of the validation set
rmse_results %>% knitr::kable()

# Validation test
# We compute first the user effect for validation set 

user_avgs_validation <- validation %>% 
  left_join(movie_avgs, by='movieId') %>%
  group_by(userId) %>%
  summarize(b_u = mean(rating - mu - b_i))

predicted_ratings <- validation %>% 
  left_join(movie_avgs, by='movieId') %>%
  left_join(user_avgs_validation, by='userId') %>%
  mutate(pred = mu + b_i + b_u) %>%
  .$pred

model_rmse_validation <- RMSE(predicted_ratings, validation$rating)
model_rmse_validation



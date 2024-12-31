// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract DineRate {
  struct Review {
    address reviewer;
    string facilityName;
    string facilityImage;
    uint8 starRating;
    string comment;
    string location;
    uint256 timestamp;
  }

  struct FacilityStats {
    Review[] reviews;
    uint8 averageRating;
  }

  Review[] private reviews;

  event ReviewCreated(
    address indexed reviewer,
    string facilityName,
    uint8 starRating,
    uint256 timestamp
  );

  function createReview(
    string memory facilityName,
    string memory facilityImage,
    uint8 starRating,
    string memory comment,
    string memory location
  ) public {
    require(starRating >= 1 && starRating <= 5, "Star rating must be between 1 and 5");
    require(bytes(facilityName).length > 0, "Facility name cannot be empty");

    reviews.push(Review({
      reviewer: msg.sender,
      facilityName: facilityName,
      facilityImage: facilityImage,
      starRating: starRating,
      comment: comment,
      location: location,
      timestamp: block.timestamp
    }));

    emit ReviewCreated(msg.sender, facilityName, starRating, block.timestamp);
  }

  function getReviewsByFacility(string memory facilityName) public view returns (FacilityStats memory) {
    uint count = 0;
    uint256 totalRating = 0;

    for (uint i = 0; i < reviews.length; i++) {
      if (keccak256(bytes(reviews[i].facilityName)) == keccak256(bytes(facilityName))) {
        count++;
        totalRating += reviews[i].starRating * 2; // Multiply each rating by 2
      }
    }

    Review[] memory facilityReviews = new Review[](count);
    uint currentIndex = 0;

    for (uint i = 0; i < reviews.length; i++) {
      if (keccak256(bytes(reviews[i].facilityName)) == keccak256(bytes(facilityName))) {
        facilityReviews[currentIndex] = reviews[i];
        currentIndex++;
      }
    }

    uint8 avgRating = count > 0 ? uint8(totalRating / count) : 0; // Will give results like 2, 3, 4, 5, 6, 7, 8, 9, 10
    // Divide by 2 when displaying in frontend to get 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0

    return FacilityStats({
      reviews: facilityReviews,
      averageRating: avgRating
    });
  }

  function getReviewsByUser(address user) public view returns (Review[] memory) {
    uint count = 0;
    for (uint i = 0; i < reviews.length; i++) {
      if (reviews[i].reviewer == user) {
        count++;
      }
    }

    Review[] memory userReviews = new Review[](count);
    uint currentIndex = 0;

    for (uint i = 0; i < reviews.length; i++) {
      if (reviews[i].reviewer == user) {
        userReviews[currentIndex] = reviews[i];
        currentIndex++;
      }
    }

    return userReviews;
  }

  function getAllReviews() public view returns (Review[] memory) {
    return reviews;
  }

  function getReviewsByLocation(string memory location) public view returns (Review[] memory) {
    uint count = 0;
    for (uint i = 0; i < reviews.length; i++) {
      if (keccak256(bytes(reviews[i].location)) == keccak256(bytes(location))) {
        count++;
      }
    }

    Review[] memory locationReviews = new Review[](count);
    uint currentIndex = 0;

    for (uint i = 0; i < reviews.length; i++) {
      if (keccak256(bytes(reviews[i].location)) == keccak256(bytes(location))) {
        locationReviews[currentIndex] = reviews[i];
        currentIndex++;
      }
    }

    return locationReviews;
  }
}